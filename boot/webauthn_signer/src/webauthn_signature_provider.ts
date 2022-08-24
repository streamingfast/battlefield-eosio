import { ApiInterfaces, Serialize, Numeric } from 'eosjs';
import { ec } from 'elliptic';
import crypto, { BinaryLike } from 'crypto';
import { PushTransactionArgs } from 'eosjs/dist/eosjs-rpc-interfaces';
import { hexToUint8Array, arrayToHex } from 'eosjs/dist/eosjs-serialize';
import { Key, newSerialBuffer } from '.';
import open from 'open';
import debugFactory from 'debug';

const debug = debugFactory('webauthn:provider');

export type Assertion = {
  signatureHex: string;
  authenticatorDataHex: string;
  clientDataJsonHex: string;
};

export class WaSignatureProvider implements ApiInterfaces.SignatureProvider {
  public keys = new Map<string, Key>();
  public assertions = new Map<string, Assertion>();

  public async getAvailableKeys(): Promise<string[]> {
    return Array.from(this.keys.keys());
  }

  public async sign({
    chainId,
    requiredKeys,
    serializedTransaction,
  }: ApiInterfaces.SignatureProviderArgs): Promise<PushTransactionArgs> {
    debug('Required keys %O', requiredKeys);

    const signBuf = newSerialBuffer();
    signBuf.pushArray(Serialize.hexToUint8Array(chainId));
    signBuf.pushArray(serializedTransaction);
    signBuf.pushArray(new Uint8Array(32));
    const digest = sha256(signBuf.asUint8Array());
    debug('Digest to sign %s', Serialize.arrayToHex(digest));

    const signatures = [] as string[];
    for (const requiredKey of requiredKeys) {
      const key = this.keys.get(requiredKey);
      if (!key) {
        throw new Error(`failed to find required key ${key}`);
      }

      await this.waitForAssertion(key, arrayToHex(digest));
      const assertion = this.assertions.get(key.key);
      if (!assertion) {
        throw new Error(`logic error since assertion should be present now`);
      }

      const e = new ec('p256') as any;
      const pubKey = e
        .keyFromPublic(Numeric.stringToPublicKey(key.key).data.subarray(0, 33))
        .getPublic();

      function fixup(x: Uint8Array) {
        const a = Array.from(x);
        while (a.length < 32) a.unshift(0);
        while (a.length > 32)
          if (a.shift() !== 0) throw new Error('Signature has an r or s that is too big');
        return new Uint8Array(a);
      }

      const der = newSerialBuffer(hexToUint8Array(assertion.signatureHex));
      if (der.get() !== 0x30) throw new Error('Signature missing DER prefix');
      if (der.get() !== der.array.length - 2) throw new Error('Signature has bad length');
      if (der.get() !== 0x02) throw new Error('Signature has bad r marker');
      const r = fixup(der.getUint8Array(der.get()));
      if (der.get() !== 0x02) throw new Error('Signature has bad s marker');
      const s = fixup(der.getUint8Array(der.get()));

      const whatItReallySigned = newSerialBuffer();
      whatItReallySigned.pushArray(hexToUint8Array(assertion.authenticatorDataHex));
      whatItReallySigned.pushArray(sha256(hexToUint8Array(assertion.clientDataJsonHex)));

      const hash = sha256(whatItReallySigned.asUint8Array());
      const recid = e.getKeyRecoveryParam(hash, hexToUint8Array(assertion.signatureHex), pubKey);

      const sigData = newSerialBuffer();
      sigData.push(recid + 27 + 4);
      sigData.pushArray(r);
      sigData.pushArray(s);
      sigData.pushBytes(hexToUint8Array(assertion.authenticatorDataHex));
      sigData.pushBytes(hexToUint8Array(assertion.clientDataJsonHex));

      const sig = Numeric.signatureToString({
        type: Numeric.KeyType.wa,
        data: sigData.asUint8Array().slice(),
      });
      signatures.push(sig);
    }

    return { signatures, serializedTransaction };
  }

  public async waitForAssertion(key: Key, digestHex: string) {
    debug('Opening browser');
    await open(
      `https://localhost:8443/transfer.html?publicKey=${key.key}&credentialId=${key.credentialId}&digest=${digestHex}`,
    );

    debug('Waiting for assertion to come back from browser ...');
    const start = Date.now();
    while (this.assertions === undefined || this.assertions.get(key.key) === undefined) {
      if (Date.now() - start > 7500) {
        debug('Still waiting for assertions to come back from browser ...');
      }

      await waitFor(250);
    }

    debug('Got assertions from browser, continuing...');
  }
}

export async function waitFor(value: number) {
  return new Promise(resolve => setTimeout(resolve, value));
}

function sha256(input: BinaryLike) {
  return new Uint8Array(
    crypto
      .createHash('sha256')
      .update(input)
      .digest(),
  );
}
