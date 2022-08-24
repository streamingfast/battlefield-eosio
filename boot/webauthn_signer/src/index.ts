import * as cbor from 'cbor';
import { Api, JsonRpc, Serialize, Numeric } from 'eosjs';
import express from 'express';
import https from 'https';
import fs from 'fs';
import * as util from 'util';
import { ServerResponse } from 'http';
import { WaSignatureProvider, Assertion, waitFor } from './webauthn_signature_provider';
import fetch from 'node-fetch';
import { TextEncoder, TextDecoder } from 'util';
import debugFactory from 'debug';

const KEYS_DB_FILE_PATH = '../webauthn_keys_db.json';
const debug = debugFactory('webauthn:server');

export interface Key {
  credentialId: string;
  key: string;
}

interface AddKeyRequest {
  relayPartyId: string;
  rawId: string;
  attestationObject: string;
  clientDataJSON: string;
}

const enum AttestationFlags {
  userPresent = 0x01,
  userVerified = 0x04,
  attestedCredentialPresent = 0x40,
  extensionDataPresent = 0x80,
}

const enum UserPresence {
  none = 0,
  present = 1,
  verified = 2,
}

async function main() {
  loadKeys();

  const app = express();
  const server = https.createServer(
    {
      key: fs.readFileSync('./localhost-key.pem'),
      cert: fs.readFileSync('./localhost.pem'),
      passphrase: '',
    },
    app,
  );

  app.use('/generate.html', pipeFile('./src/generate.html'));
  app.use('/transfer.html', pipeFile('./src/transfer.html'));
  app.use('/client.js', pipeFile('./src/client.js'));

  app.use(express.json());
  app.use('/add_key', async (req, res) => {
    debug('Received add_key request %O', req.body);
    const key = await addKey(req.body as AddKeyRequest);
    res.json({ publicKey: key });

    console.log('Generated key', key);
    setTimeout(() => {
      console.log('Quitting generation');
      process.exit(0);
    }, 0);
  });

  app.use('/add_assertion', async (req, res) => {
    debug('Received add_assertion request %O', req.body);
    persistAssertion(req.body as { publicKey: string; assertion: Assertion });

    await waitForTransactionPush();
    if (pushError) {
      res.json({ error: pushError });
    } else {
      res.json({});
    }

    setTimeout(() => {
      console.log('Quitting transfer');
      process.exit(0);
    }, 0);
  });

  server.listen(8443);

  const lastArgumentIndex = process.argv.length - 1;
  let unknownCommand = true;

  if (process.argv[lastArgumentIndex] === 'transfer') {
    unknownCommand = false;

    if (keys.length < 1) {
      console.log(
        "No previously generated WebAuthM public key found, please perform the '/generate.html' flow first",
      );
      process.exit(1);
    }

    await pushTransaction();

    if (pushError != null) {
      console.log(`Unable to correctly pushed transaction: ${pushError}`);
      process.exit(1);
    }

    // Do not exit yet, the browser is going to call back us with the final notification that everything is good
  }

  if (process.argv[lastArgumentIndex] === 'doctor') {
    if (keys.length < 1) {
      console.log(
        "No previously generated WebAuthM public key found, please perform the '/generate.html' flow first",
      );
      process.exit(1);
    }

    const key = keys[0].key;
    const keyMaterial = key.replace('PUB_WA_', '');

    console.log(`Public Key: ${key}`);
    console.log(`Public Key Material: ${keyMaterial}`);

    const decodeKeyMaterial = Numeric.base58ToBinary(0, key.replace('PUB_WA_', ''));
    console.log(`Decoded Key Material: ${Serialize.arrayToHex(decodeKeyMaterial)}`);

    const serializeBuffer = newSerialBuffer();
    serializeBuffer.pushPublicKey(key);

    const encodedKey = serializeBuffer.asUint8Array();
    console.log(`EOSIO ABI Encoded HEX: ${Serialize.arrayToHex(encodedKey)}`);

    const deserializeBuffer = newSerialBuffer(encodedKey);
    const deserializedKey = deserializeBuffer.getPublicKey();
    console.log(`EOSIO ABI Decoded HEX: ${deserializedKey}`);

    process.exit(0);
  }

  if (unknownCommand) {
    debug(
      'Arguments %o',
      process.argv[lastArgumentIndex],
      process.argv[lastArgumentIndex] === 'transfer',
    );
    console.log('No command received, listening on :8443 (Ctrl-C to quit)');
  }
}

async function pushTransaction() {
  try {
    const api = new Api({
      rpc: new JsonRpc('http://localhost:9898', { fetch }),
      textDecoder: new TextDecoder(),
      textEncoder: new TextEncoder(),
      signatureProvider,
    });

    const data = {
      actions: [
        {
          account: 'eosio.token',
          name: 'transfer',
          data: {
            from: 'battlefeeld4',
            to: 'eosio',
            quantity: '1.0000 EOS',
            memo: '',
          },
          authorization: [
            {
              actor: 'battlefeeld4',
              permission: 'active',
            },
          ],
        },
      ],
    };

    const response = await api.transact(data, {
      blocksBehind: 3,
      expireSeconds: 60 * 60,
    });

    debug('Transaction push response %O', response);
  } catch (error) {
    debug('Push error occurred %O', error);
    pushError = error;
  }

  pushCompleted = true;
}

let pushCompleted = false;
let pushError: any;

async function waitForTransactionPush() {
  debug('Waiting transaction to be pushed ...');

  const start = Date.now();
  while (!pushCompleted) {
    if (Date.now() - start > 7500) {
      debug('Still waiting transaction to be pushed ...');
    }

    await waitFor(250);
  }
}

async function addKey(keyRequest: AddKeyRequest) {
  const decoded = await decodeKey(keyRequest);

  debug('Saving key %O', decoded);
  persistKey(decoded);

  return decoded.key;
}

async function decodeKey(keyRequest: AddKeyRequest) {
  const att = await (cbor as any).decodeFirst(
    Serialize.hexToUint8Array(keyRequest.attestationObject),
  );
  const data = new DataView(att.authData.buffer);

  let pos = 30; // skip unknown
  pos += 32; // RP ID hash

  const flags = data.getUint8(pos++);
  const signCount = data.getUint32(pos);
  pos += 4;

  if (!(flags & AttestationFlags.attestedCredentialPresent))
    throw new Error('attestedCredentialPresent flag not set');

  const aaguid = Serialize.arrayToHex(new Uint8Array(data.buffer, pos, 16));
  pos += 16;

  const credentialIdLength = data.getUint16(pos);
  pos += 2;

  const credentialId = new Uint8Array(data.buffer, pos, credentialIdLength);
  pos += credentialIdLength;

  const pubKey = await (cbor as any).decodeFirst(new Uint8Array(data.buffer, pos));

  if (Serialize.arrayToHex(credentialId) !== keyRequest.rawId)
    throw new Error('Credential ID does not match');
  if (pubKey.get(1) !== 2) throw new Error('Public key is not EC2');
  if (pubKey.get(3) !== -7) throw new Error('Public key is not ES256');
  if (pubKey.get(-1) !== 1) throw new Error('Public key has unsupported curve');
  const x = pubKey.get(-2);
  const y = pubKey.get(-3);
  if (x.length !== 32 || y.length !== 32) throw new Error('Public key has invalid X or Y size');

  const ser = newSerialBuffer();
  ser.push(y[31] & 1 ? 3 : 2);
  ser.pushArray(x);
  ser.push(flagsToPresence(flags));
  ser.pushString(keyRequest.relayPartyId);
  const compact = ser.asUint8Array();

  const key = Numeric.publicKeyToString({
    type: Numeric.KeyType.wa,
    data: compact,
  });

  return {
    flags: ('00' + flags.toString(16)).slice(-2),
    signCount,
    aaguid,
    credentialIdLength,
    credentialId: Serialize.arrayToHex(credentialId),
    rpid: keyRequest.relayPartyId,
    presence: flagsToPresence(flags),
    x: Serialize.arrayToHex(x),
    y: Serialize.arrayToHex(y),
    compact: Serialize.arrayToHex(compact),
    key,
  };
}

let keys = [] as Key[];
const signatureProvider = new WaSignatureProvider();
function loadKeys() {
  try {
    keys = JSON.parse(fs.readFileSync(KEYS_DB_FILE_PATH, 'utf8'));

    if (keys.length > 0) {
      signatureProvider.keys = new Map();
      signatureProvider.keys.set(keys[0].key, keys[0]);
    }
  } catch (error) {}
}

function persistKey(key: Key) {
  try {
    keys = [key];
    signatureProvider.keys = new Map();
    signatureProvider.keys.set(key.key, key);

    fs.writeFileSync(KEYS_DB_FILE_PATH, JSON.stringify(keys, null, '  '));
  } catch (e) {
    debug('Unable to write keys to disk %O', e);
  }
}

function persistAssertion(request: { publicKey: string; assertion: Assertion }) {
  // The provider listen for changes on this and get notified
  signatureProvider.assertions = new Map();
  signatureProvider.assertions.set(request.publicKey, request.assertion);
}

function flagsToPresence(flags: number) {
  if (flags & AttestationFlags.userVerified) return UserPresence.verified;
  else if (flags & AttestationFlags.userPresent) return UserPresence.present;
  else return UserPresence.none;
}

function pipeFile(filePath: string) {
  return (req: any, res: ServerResponse) => {
    fs.createReadStream(filePath).pipe(res);
  };
}

export function newSerialBuffer(array?: Uint8Array) {
  return new Serialize.SerialBuffer({
    textDecoder: new TextDecoder(),
    textEncoder: new TextEncoder(),
    array,
  });
}

main().catch(error => {
  console.log('Unknown error occurred', error);
  process.exit(1);
});
