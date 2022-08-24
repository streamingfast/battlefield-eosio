async function transfer() {
  const urlParams = new URLSearchParams(window.location.search);
  const publicKey = urlParams.get('publicKey');
  const credentialId = urlParams.get('credentialId');
  const digest = urlParams.get('digest');

  appendMessage(`Generating assertion for ${publicKey} ...`);
  appendMessage(`CredentialID ${credentialId}`);
  appendMessage(`Digest ${digest}`);

  const assertion = await navigator.credentials.get({
    publicKey: {
      timeout: 60000,
      allowCredentials: [
        {
          id: hexToByteArray(credentialId),
          type: 'public-key',
        },
      ],
      challenge: hexToByteArray(digest),
    },
  });

  const result = await postData('/add_assertion', {
    publicKey: publicKey,
    assertion: {
      signatureHex: byteArrayToHex(assertion.response.signature),
      authenticatorDataHex: byteArrayToHex(assertion.response.authenticatorData),
      clientDataJsonHex: byteArrayToHex(assertion.response.clientDataJSON),
    },
  });

  if (result.error) {
    logError('Unable to correctly push transaction');
  } else {
    appendMessage('Successuflly pushed transaction!');
    closeTab(2500);
  }
}

async function generate() {
  try {
    appendMessage('Generating key...');
    const { rawId, response: credentialsResponse } = await navigator.credentials.create({
      publicKey: {
        rp: { id: 'localhost', name: 'dfuse' },
        user: {
          id: new Uint8Array(16),
          name: 'dev@dfuse.io',
          displayName: 'Bugs Bunny',
        },
        pubKeyCredParams: [
          {
            type: 'public-key',
            alg: -7,
          },
        ],
        timeout: 60000,
        challenge: hexToByteArray(
          '8c0a26ff2291c1e9b94e2e171a986a73719d4348d5a76a157e38945277970fef',
        ).buffer,
      },
    });

    const keyResponse = await postData('/add_key', {
      relayPartyId: 'localhost',
      rawId: byteArrayToHex(rawId),
      attestationObject: byteArrayToHex(credentialsResponse.attestationObject),
      clientDataJSON: byteArrayToHex(credentialsResponse.clientDataJSON),
    });

    appendMessage(`Generated Public Key`);
    appendMessage(keyResponse.publicKey, 'public_key');

    setTimeout(() => {
      document.body.focus();
      copyToClipboard(keyResponse.publicKey);

      closeTab(2500);
    }, 250);
  } catch (error) {
    logError('Unable to generate key', error);
  }
}

function appendMessage(message, tag) {
  const node = document.createElement('p');
  if (tag != null) {
    node.setAttribute('id', tag);
  }
  node.appendChild(document.createTextNode(message));

  document.getElementById('main').appendChild(node);
}

function logError(message, error) {
  const node = document.createElement('p');
  node.setAttribute('style', 'color: red;');
  node.appendChild(document.createTextNode(message + ':' + error));

  document.getElementById('main').appendChild(node);

  console.log(error);
}

async function getData(path) {
  return await fetch(`https://localhost:8443${path}`).then(response => response.json());
}

async function postData(path, data = {}) {
  const response = await fetch(`https://localhost:8443${path}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(data),
  });

  return await response.json();
}

function hexToByteArray(input) {
  const toHex = () => input.match(/[\da-f]{2}/gi).map(x => parseInt(x, 16));

  return new Uint8Array(toHex());
}

function byteArrayToHex(data) {
  let result = '';
  for (const x of new Uint8Array(data)) {
    result += ('00' + x.toString(16)).slice(-2);
  }
  return result.toUpperCase();
}

function closeTab(delayInMs) {
  appendMessage(`Closing tab in ${delayInMs}ms`);
  setTimeout(() => {
    window.close();
  }, delayInMs);
}

function copyToClipboard(input) {
  navigator.clipboard.writeText(input).then(
    () => {
      appendMessage('Copied to clipboard!');
    },
    error => {
      logError('Copy to clipboard failed', err);
    },
  );
}
