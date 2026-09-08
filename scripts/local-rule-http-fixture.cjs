const http = require('node:http');

const port = Number(process.env.LOCAL_RULE_FIXTURE_PORT || 18997);
const server = http.createServer((request, response) => {
  const url = new URL(request.url, `http://127.0.0.1:${port}`);
  if (url.pathname === '/redirect') {
    response.writeHead(302, { Location: '/echo', 'Set-Cookie': 'fixture=redirect; Path=/' });
    response.end('redirect body');
    return;
  }
  if (url.pathname === '/missing') {
    response.writeHead(404, { 'Content-Type': 'application/json' });
    response.end('{"error":"fixture missing"}');
    return;
  }
  if (url.pathname === '/render') {
    response.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8', 'Set-Cookie': 'fixture=browser; Path=/' });
    response.end('<!doctype html><html><head><title>Fixture</title></head><body><main id="chapter">initial</main>' +
      '<script>window.__BOOK_STATE__={title:"rendered state"};setTimeout(function(){document.querySelector("#chapter").innerHTML="<p>rendered chapter</p>";},150);</script></body></html>');
    return;
  }
  if (url.pathname === '/render-media') {
    response.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    response.end('<!doctype html><html><body><audio id="player" preload="none"></audio>' +
      '<script>setTimeout(function(){document.querySelector("#player").src="/fixture-audio.mp3";},100);</script></body></html>');
    return;
  }
  if (url.pathname === '/interactive') {
    response.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    response.end('<!doctype html><html><body><form id="form" action="/navigated"><input id="query" name="q">' +
      '<button id="go" type="button">Load</button><button id="send" type="submit">Submit</button></form>' +
      '<p id="result">waiting</p><p id="events">0</p><p id="clicks">0</p>' +
      '<script>window.pageState={count:0};document.querySelector("#query").addEventListener("input",function(){document.querySelector("#events").textContent=String(Number(document.querySelector("#events").textContent)+1);});' +
      'document.querySelector("#go").onclick=function(){window.pageState.count++;document.querySelector("#clicks").textContent=String(window.pageState.count);' +
      'setTimeout(function(){document.querySelector("#result").textContent="loaded:"+document.querySelector("#query").value;},100);};</script></body></html>');
    return;
  }
  if (url.pathname === '/navigated') {
    response.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    response.end('<!doctype html><html><body><p id="result">navigation complete</p></body></html>');
    return;
  }
  if (url.pathname === '/library.js') {
    response.writeHead(200, { 'Content-Type': 'application/javascript' });
    response.end('function fixtureLibrary(value){return "library:"+value;}');
    return;
  }
  if (url.pathname.startsWith('/management/')) {
    const mode = url.searchParams.get('mode') || 'normal';
    const query = '?mode=' + encodeURIComponent(mode);
    let payload;
    if (url.pathname === '/management/explore') {
      payload = { books: mode === 'empty' ? [] : [
        { name: 'Management fixture', bookUrl: '/management/book' + query }
      ] };
    } else if (url.pathname === '/management/book') {
      payload = { name: 'Management fixture', tocUrl: '/management/toc' + query };
    } else if (url.pathname === '/management/toc') {
      payload = { chapters: [{ name: 'Chapter 1', url: '/management/chapter' + query,
        isPay: mode === 'paid', isVip: false, isVolume: false }] };
    } else if (url.pathname === '/management/chapter') {
      payload = { content: 'Management fixture chapter text.' };
    }
    if (payload !== undefined) {
      const send = () => {
        response.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8' });
        response.end(JSON.stringify(payload));
      };
      if (mode === 'slow' && url.pathname === '/management/explore') setTimeout(send, 750);
      else send();
      return;
    }
  }
  let body = '';
  request.on('data', chunk => { body += chunk; });
  request.on('end', () => {
    response.writeHead(200, { 'Content-Type': 'application/json' });
    response.end(JSON.stringify({ method: request.method, cookie: request.headers.cookie || '', body, url: url.pathname }));
  });
});

server.listen(port, '127.0.0.1', () => console.log(`Fixture ready at http://127.0.0.1:${port}`));
