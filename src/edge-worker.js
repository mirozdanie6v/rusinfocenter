const AWG_HOST = 'awg.viiversion.com';
const AWG_ORIGIN = 'https://d5dff0rbrgoi4lc2t9lu.l5v6loqa.apigw.yandexcloud.net';

export default {
  async fetch(request, env) {
    const incoming = new URL(request.url);

    if (incoming.hostname === AWG_HOST) {
      const target = new URL(incoming.pathname + incoming.search, AWG_ORIGIN);
      const headers = new Headers(request.headers);
      headers.delete('host');

      const upstream = await fetch(new Request(target.toString(), {
        method: request.method,
        headers,
        body: request.method === 'GET' || request.method === 'HEAD' ? undefined : request.body,
        redirect: 'manual'
      }));

      const responseHeaders = new Headers(upstream.headers);
      const location = responseHeaders.get('location');
      if (location && location.startsWith(AWG_ORIGIN)) {
        responseHeaders.set('location', location.replace(AWG_ORIGIN, 'https://awg.viiversion.com'));
      }

      return new Response(upstream.body, {
        status: upstream.status,
        statusText: upstream.statusText,
        headers: responseHeaders
      });
    }

    return env.ASSETS.fetch(request);
  }
};
