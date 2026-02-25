declare module 'noise-handshake' {
  interface Keypair {
    publicKey: Buffer;
    secretKey: Buffer;
  }

  interface CipherState {
    key: Buffer;
    nonce: number;
    encrypt(plaintext: Buffer, ad?: Buffer): Buffer;
    decrypt(ciphertext: Buffer, ad?: Buffer): Buffer;
    hasKey: boolean;
  }

  interface NoiseOptions {
    psk?: Buffer;
  }

  class Noise {
    s: Keypair;
    rs: Buffer | null;
    tx: CipherState | null;
    rx: CipherState | null;
    complete: boolean;
    hash: Buffer;

    constructor(pattern: string, initiator: boolean, staticKeypair?: Keypair | null, opts?: NoiseOptions);
    initialise(prologue: Buffer, remoteStaticKey: Buffer): void;
    send(payload?: Buffer): Buffer;
    recv(buf: Buffer): Buffer;
  }

  export = Noise;
}

declare module 'noise-handshake/cipher' {
  interface CipherState {
    key: Buffer;
    nonce: number;
    hasKey: boolean;
  }

  class Cipher {
    constructor(cipherState: CipherState);
    encrypt(plaintext: Buffer, ad?: Buffer): Buffer;
    decrypt(ciphertext: Buffer, ad?: Buffer): Buffer;
  }

  export = Cipher;
}

declare module 'noise-handshake/dh' {
  interface Keypair {
    publicKey: Buffer;
    secretKey: Buffer;
  }

  interface DH {
    DHLEN: number;
    PKLEN: number;
    SKLEN: number;
    SEEDLEN: number;
    ALG: string;
    generateKeyPair(privKey?: Buffer): Keypair;
    generateSeedKeyPair(seed: Buffer): Keypair;
    dh(publicKey: Buffer, keyPair: Keypair): Buffer;
  }

  function createDH(): DH;
  export = createDH;
}
