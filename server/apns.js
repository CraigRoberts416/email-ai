const crypto = require('node:crypto');
const fs = require('node:fs');
const http2 = require('node:http2');

// Apple documents device tokens as variable-length opaque bytes, not a fixed
// 64-character identifier. The native app submits their hexadecimal encoding.
function isAPNsToken(token) {
  return typeof token === 'string' && /^(?:[a-f0-9]{2}){16,128}$/i.test(token);
}

function createAPNsTransport({ env = process.env, connect = http2.connect, now = Date.now, readFile = fs.readFileSync } = {}) {
  let session;
  let jwt;
  let issuedAt = 0;

  function configuration() {
    const missing = ['APNS_KEY_ID', 'APNS_TEAM_ID', 'APNS_TOPIC'].filter(key => !env[key]);
    if (!env.APNS_PRIVATE_KEY && !env.APNS_PRIVATE_KEY_PATH) missing.push('APNS_PRIVATE_KEY or APNS_PRIVATE_KEY_PATH');
    if (missing.length) {
      const error = new Error(`Native push is not configured: ${missing.join(', ')}`);
      error.code = 'APNS_NOT_CONFIGURED';
      throw error;
    }
    const environment = env.APNS_ENVIRONMENT || 'production';
    if (!['production', 'sandbox'].includes(environment)) {
      throw new Error('APNS_ENVIRONMENT must be production or sandbox');
    }
    return {
      topic: env.APNS_TOPIC,
      endpoint: environment === 'sandbox' ? 'https://api.sandbox.push.apple.com' : 'https://api.push.apple.com',
    };
  }

  function providerToken() {
    // Apple requires renewal between 20 and 60 minutes. Reuse for 50 minutes;
    // generating a new token for every email can itself trigger rate limits.
    const seconds = Math.floor(now() / 1000);
    if (jwt && seconds >= issuedAt && seconds - issuedAt < 50 * 60) return jwt;
    const key = env.APNS_PRIVATE_KEY
      ? env.APNS_PRIVATE_KEY.replace(/\\n/g, '\n')
      : readFile(env.APNS_PRIVATE_KEY_PATH, 'utf8');
    const header = Buffer.from(JSON.stringify({ alg: 'ES256', kid: env.APNS_KEY_ID })).toString('base64url');
    const claims = Buffer.from(JSON.stringify({ iss: env.APNS_TEAM_ID, iat: seconds })).toString('base64url');
    const signingInput = `${header}.${claims}`;
    const signature = crypto.sign('sha256', Buffer.from(signingInput), {
      key, dsaEncoding: 'ieee-p1363',
    }).toString('base64url');
    issuedAt = seconds;
    jwt = `${signingInput}.${signature}`;
    return jwt;
  }

  async function send(deviceToken, payload, { collapseId } = {}) {
    if (!isAPNsToken(deviceToken)) throw new Error('Invalid APNs device token');
    const config = configuration();
    const authorization = providerToken();
    const body = JSON.stringify(payload);
    if (Buffer.byteLength(body) > 4096) throw new Error('APNs payload exceeds 4096 bytes');
    if (!session || session.closed || session.destroyed) {
      session = connect(config.endpoint);
      const current = session;
      current.on('error', () => { if (session === current) session = undefined; });
      current.on('goaway', () => {
        if (session === current) session = undefined;
        current.close();
      });
    }

    // A badge is an alert-type push, even without a banner or sound. Sending
    // it as "background" violates Apple's payload contract and can drop it.
    const visible = payload.aps?.alert || payload.aps?.sound || payload.aps?.badge !== undefined;
    return new Promise((resolve, reject) => {
      const connection = session;
      const request = connection.request({
        ':method': 'POST',
        ':path': `/3/device/${deviceToken}`,
        authorization: `bearer ${authorization}`,
        'apns-topic': config.topic,
        'apns-push-type': visible ? 'alert' : 'background',
        'apns-priority': visible ? '10' : '5',
        'apns-expiration': String(Math.floor(now() / 1000) + 3600),
        ...(collapseId ? { 'apns-collapse-id': collapseId } : {}),
        'content-type': 'application/json',
      });
      let status;
      let response = '';
      let settled = false;
      const finish = (error, result) => {
        if (settled) return;
        settled = true;
        clearTimeout(timeout);
        connection.removeListener('error', onError);
        if (error) reject(error);
        else resolve(result);
      };
      const onError = error => finish(error);
      const timeout = setTimeout(() => {
        finish(new Error('APNs request timed out'));
        request.close(http2.constants.NGHTTP2_CANCEL);
      }, 10000);
      connection.once('error', onError);
      request.on('response', headers => { status = headers[':status']; });
      request.setEncoding('utf8');
      request.on('data', chunk => { if (response.length < 4096) response += chunk; });
      request.once('error', onError);
      request.once('end', () => {
        if (status === 200) return finish(null, { status: 'ok' });
        let reason = 'APNsRejected';
        try { reason = JSON.parse(response).reason || reason; } catch { /* no JSON response */ }
        const error = new Error(`APNs rejected push: ${reason}`);
        error.code = reason;
        error.statusCode = status;
        finish(error);
      });
      request.end(body);
    });
  }

  return {
    send,
    isConfigured: () => { try { configuration(); return true; } catch { return false; } },
    close: () => { session?.close(); session = undefined; },
  };
}

module.exports = { createAPNsTransport, isAPNsToken };
