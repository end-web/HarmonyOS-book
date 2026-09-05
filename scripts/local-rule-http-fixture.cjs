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
  if (url.pathname === '/library.js') {
    response.writeHead(200, { 'Content-Type': 'application/javascript' });
    response.end('function fixtureLibrary(value){return "library:"+value;}');
    return;
  }
  let body = '';
  request.on('data', chunk => { body += chunk; });
  request.on('end', () => {
    response.writeHead(200, { 'Content-Type': 'application/json' });
    response.end(JSON.stringify({ method: request.method, cookie: request.headers.cookie || '', body, url: url.pathname }));
  });
});

server.listen(port, '127.0.0.1', () => console.log(`Fixture ready at http://127.0.0.1:${port}`));
