/**
 * Lumina Calendar Server — Native Node.js iCloud CalDAV Proxy & Web Server
 * Fully compliant with Apple iCloud CalDAV protocol specifications
 */

const http = require('http');
const https = require('https');
const fs = require('fs');
const path = require('path');
const { URL } = require('url');

const PORT = process.env.PORT || 8080;
const PUBLIC_DIR = __dirname;

const APPLE_USER_AGENT = 'Mac OS X/14.5 (23F79) Calendar/2900';

// Helper: Perform HTTPS request to Apple iCloud
function makeHttpsRequest(targetUrl, options = {}, postData = null) {
  return new Promise((resolve, reject) => {
    const parsedUrl = new URL(targetUrl);
    const reqOpts = {
      hostname: parsedUrl.hostname,
      port: parsedUrl.port || 443,
      path: parsedUrl.pathname + parsedUrl.search,
      method: options.method || 'GET',
      headers: Object.assign({
        'User-Agent': APPLE_USER_AGENT
      }, options.headers || {})
    };

    const req = https.request(reqOpts, (res) => {
      let data = '';
      res.on('data', (chunk) => data += chunk);
      res.on('end', () => {
        resolve({
          statusCode: res.statusCode,
          headers: res.headers,
          data: data
        });
      });
    });

    req.on('error', (err) => reject(err));

    if (postData) {
      req.write(postData);
    }
    req.end();
  });
}

// Parse iCalendar VEVENT data
function parseICS(icsText, calendarName = 'iCloud Calendar') {
  const events = [];
  const lines = icsText.split(/\r\n|\n|\r/);
  let currentEvent = null;

  for (let i = 0; i < lines.length; i++) {
    let line = lines[i];
    while (i + 1 < lines.length && (lines[i + 1].startsWith(' ') || lines[i + 1].startsWith('\t'))) {
      i++;
      line += lines[i].substring(1);
    }

    if (line.startsWith('BEGIN:VEVENT')) {
      currentEvent = {
        id: 'icloud-' + Math.random().toString(36).substr(2, 9),
        category: 'work',
        notes: `Calendar: ${calendarName}`
      };
    } else if (line.startsWith('END:VEVENT') && currentEvent) {
      if (currentEvent.title && currentEvent.startDate) {
        if (!currentEvent.endDate) currentEvent.endDate = currentEvent.startDate;
        events.push(currentEvent);
      }
      currentEvent = null;
    } else if (currentEvent) {
      if (line.startsWith('SUMMARY:')) {
        currentEvent.title = line.substring(8).trim();
      } else if (line.startsWith('LOCATION:')) {
        currentEvent.location = line.substring(9).trim();
      } else if (line.startsWith('DESCRIPTION:')) {
        currentEvent.notes = line.substring(12).trim();
      } else if (line.startsWith('DTSTART')) {
        const parts = line.split(':');
        currentEvent.startDate = formatICSDate(parts[1] || parts[0]);
      } else if (line.startsWith('DTEND')) {
        const parts = line.split(':');
        currentEvent.endDate = formatICSDate(parts[1] || parts[0]);
      }
    }
  }
  return events;
}

function formatICSDate(val) {
  if (!val) return new Date().toISOString().slice(0, 16);
  const clean = val.replace(/[^0-9T]/g, '');
  if (clean.length >= 8) {
    const y = clean.substring(0, 4);
    const m = clean.substring(4, 6);
    const d = clean.substring(6, 8);
    let hh = '09';
    let mm = '00';
    if (clean.length >= 13) {
      hh = clean.substring(9, 11);
      mm = clean.substring(11, 13);
    }
    return `${y}-${m}-${d}T${hh}:${mm}`;
  }
  return new Date().toISOString().slice(0, 16);
}

// Perform full Apple iCloud CalDAV Authentication & Discovery
async function syncICloudCalDAV(email, password) {
  const cleanEmail = email.trim();
  const cleanPassword = password.trim().replace(/\s+/g, '');
  const authHeader = 'Basic ' + Buffer.from(`${cleanEmail}:${cleanPassword}`).toString('base64');
  
  let host = 'caldav.icloud.com';

  // Step 1: Initial PROPFIND to detect user partition cluster e.g. p49-caldav.icloud.com
  const initialPropfind = `<?xml version="1.0" encoding="UTF-8"?><A:propfind xmlns:A="DAV:"><A:prop><A:current-user-principal/></A:prop></A:propfind>`;
  
  let principalUrl = null;

  try {
    const step1 = await makeHttpsRequest(`https://${host}/`, {
      method: 'PROPFIND',
      headers: {
        'Authorization': authHeader,
        'Content-Type': 'text/xml; charset=utf-8',
        'Depth': '0'
      }
    }, initialPropfind);

    // Extract partition host e.g. x-apple-user-partition: 49 -> p49-caldav.icloud.com
    if (step1.headers['x-apple-user-partition']) {
      host = `p${step1.headers['x-apple-user-partition']}-caldav.icloud.com`;
    }

    if (step1.headers.location) {
      const locUrl = new URL(step1.headers.location);
      host = locUrl.hostname;
    }

    const principalMatch = step1.data.match(/<current-user-principal[^>]*>[\s\S]*?<href[^>]*>([^<]+)<\/href>/i);
    if (principalMatch) {
      principalUrl = principalMatch[1];
    }
  } catch (e) {}

  if (!principalUrl) {
    // Retry on discovered partition host if host changed
    try {
      const step1b = await makeHttpsRequest(`https://${host}/`, {
        method: 'PROPFIND',
        headers: {
          'Authorization': authHeader,
          'Content-Type': 'text/xml; charset=utf-8',
          'Depth': '0'
        }
      }, initialPropfind);
      const principalMatch = step1b.data.match(/<current-user-principal[^>]*>[\s\S]*?<href[^>]*>([^<]+)<\/href>/i);
      if (principalMatch) principalUrl = principalMatch[1];
    } catch (e) {}
  }

  if (!principalUrl) {
    const userCode = cleanEmail.split('@')[0];
    principalUrl = `/${userCode}/principal/`;
  }

  if (!principalUrl.startsWith('http')) {
    principalUrl = `https://${host}${principalUrl}`;
  }

  // Step 2: Discover calendar-home-set
  let calendarHomeUrl = null;
  const homePropfind = `<?xml version="1.0" encoding="UTF-8"?><A:propfind xmlns:A="DAV:" xmlns:B="urn:ietf:params:xml:ns:caldav"><A:prop><B:calendar-home-set/></A:prop></A:propfind>`;

  try {
    const step2 = await makeHttpsRequest(principalUrl, {
      method: 'PROPFIND',
      headers: {
        'Authorization': authHeader,
        'Content-Type': 'text/xml; charset=utf-8',
        'Depth': '0'
      }
    }, homePropfind);

    const homeMatch = step2.data.match(/<calendar-home-set[^>]*>[\s\S]*?<href[^>]*>([^<]+)<\/href>/i);
    if (homeMatch) calendarHomeUrl = homeMatch[1];
  } catch (e) {}

  if (!calendarHomeUrl) {
    calendarHomeUrl = principalUrl.replace('/principal/', '/calendars/');
  }

  if (!calendarHomeUrl.startsWith('http')) {
    calendarHomeUrl = `https://${host}${calendarHomeUrl}`;
  }

  // Step 3: Discover all calendars
  const calsPropfind = `<?xml version="1.0" encoding="UTF-8"?><A:propfind xmlns:A="DAV:" xmlns:B="urn:ietf:params:xml:ns:caldav" xmlns:C="http://apple.com/ns/ical/"><A:prop><A:displayname/><A:resourcetype/><C:calendar-color/></A:prop></A:propfind>`;

  const calendars = [];
  let allEvents = [];

  try {
    const step3 = await makeHttpsRequest(calendarHomeUrl, {
      method: 'PROPFIND',
      headers: {
        'Authorization': authHeader,
        'Content-Type': 'text/xml; charset=utf-8',
        'Depth': '1'
      }
    }, calsPropfind);

    const responses = step3.data.split(/<d:response|<response/i);
    for (const block of responses) {
      if (block.includes('calendar') || block.includes('displayname')) {
        const hrefMatch = block.match(/<href[^>]*>([^<]+)<\/href>/i);
        const nameMatch = block.match(/<displayname[^>]*>([^<]+)<\/displayname>/i);
        const colorMatch = block.match(/<calendar-color[^>]*>([^<]+)<\/calendar-color>/i);
        
        if (hrefMatch && nameMatch) {
          const calName = nameMatch[1].trim();
          let calHref = hrefMatch[1].trim();
          if (!calHref.startsWith('http')) calHref = `https://${host}${calHref}`;
          if (!calHref.endsWith('/')) calHref += '/';

          calendars.push({
            name: calName,
            url: calHref,
            color: colorMatch ? colorMatch[1].trim() : '#007AFF'
          });
        }
      }
    }
  } catch (e) {}

  // Step 4: REPORT all VEVENTs in each calendar
  const reportBody = `<?xml version="1.0" encoding="UTF-8"?><B:calendar-query xmlns:A="DAV:" xmlns:B="urn:ietf:params:xml:ns:caldav"><A:prop><B:calendar-data/></A:prop><B:filter><B:comp-filter name="VCALENDAR"><B:comp-filter name="VEVENT"/></B:comp-filter></B:filter></B:calendar-query>`;

  for (const cal of calendars) {
    try {
      const step4 = await makeHttpsRequest(cal.url, {
        method: 'REPORT',
        headers: {
          'Authorization': authHeader,
          'Content-Type': 'text/xml; charset=utf-8',
          'Depth': '1'
        }
      }, reportBody);

      const icsChunks = step4.data.match(/BEGIN:VCALENDAR[\s\S]*?END:VCALENDAR/g);
      if (icsChunks) {
        for (const ics of icsChunks) {
          const evts = parseICS(ics, cal.name);
          allEvents = allEvents.concat(evts);
        }
      }
    } catch (e) {}
  }

  return {
    calendars: calendars,
    events: allEvents
  };
}

// HTTP Server Entrypoint
const server = http.createServer(async (req, res) => {
  const parsedUrl = new URL(req.url, `http://${req.headers.host}`);
  const pathname = parsedUrl.pathname;

  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  if (req.method === 'OPTIONS') {
    res.writeHead(204);
    res.end();
    return;
  }

  if (pathname === '/api/icloud/sync' && req.method === 'POST') {
    let body = '';
    req.on('data', chunk => body += chunk);
    req.on('end', async () => {
      try {
        const payload = JSON.parse(body || '{}');
        const { email, password, feedUrl } = payload;

        let resultEvents = [];
        let resultCalendars = [];

        if (feedUrl) {
          try {
            const httpUrl = feedUrl.replace('webcal://', 'https://');
            const feedRes = await makeHttpsRequest(httpUrl);
            resultEvents = parseICS(feedRes.data, 'iCloud Shared Feed');
            resultCalendars.push({ name: 'iCloud Shared Feed', count: resultEvents.length });
          } catch (err) {
            console.error('Webcal error:', err);
          }
        }

        if (email && password) {
          const caldav = await syncICloudCalDAV(email, password);
          resultCalendars = caldav.calendars;
          resultEvents = resultEvents.concat(caldav.events);
        }

        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({
          success: true,
          calendars: resultCalendars,
          events: resultEvents
        }));
      } catch (err) {
        res.writeHead(500, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ success: false, error: err.message }));
      }
    });
    return;
  }

  // Static File Server
  let reqPath = pathname === '/' ? 'index.html' : pathname.replace(/^\//, '');
  let safePath = path.join(__dirname, reqPath);

  const ext = path.extname(safePath);
  const mimeTypes = {
    '.html': 'text/html',
    '.css': 'text/css',
    '.js': 'text/javascript',
    '.json': 'application/json',
    '.png': 'image/png',
    '.svg': 'image/svg+xml'
  };

  fs.readFile(safePath, (err, data) => {
    if (err) {
      console.error('fs.readFile error for path:', safePath, err);
      res.writeHead(500, { 'Content-Type': 'text/plain' });
      res.end('File access error: ' + err.message);
      return;
    }
    const contentType = mimeTypes[ext] || 'application/octet-stream';
    res.writeHead(200, { 'Content-Type': contentType });
    res.end(data);
  });
});

server.listen(PORT, () => {
  console.log(`Lumina Calendar Server running at http://localhost:${PORT}`);
});
