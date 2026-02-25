declare module 'noise-protocol' {
  interface Keypair {
    publicKey: Buffer;
    secretKey: Buffer;
  }

  interface HandshakeState {}

  interface Split {
    tx: Buffer;
    rx: Buffer;
  }

  interface WriteMessage {
    (state: HandshakeState, payload: Buffer, messageBuffer: Buffer): Split | undefined;
    bytes: number;
  }

  interface ReadMessage {
    (state: HandshakeState, message: Buffer, payloadBuffer: Buffer): Split | undefined;
    bytes: number;
  }

  const noise: {
    initialize(
      pattern: string,
      initiator: boolean,
      prologue: Buffer,
      s: Keypair | null,
      e: Keypair | null,
      rs: Buffer | null,
      re?: Buffer | null,
    ): HandshakeState;

    writeMessage: WriteMessage;
    readMessage: ReadMessage;
    keygen(obj?: Keypair): Keypair;
    seedKeygen(seed: Buffer): Keypair;
    destroy(state: HandshakeState): void;

    PKLEN: number;
    SKLEN: number;
  };

  export = noise;
}

declare module 'noise-protocol/cipher' {
  interface CipherModule {
    KEYLEN: number;
    NONCELEN: number;
    MACLEN: number;
    encrypt: {
      (out: Buffer, key: Buffer, nonce: Buffer, ad: Buffer, plaintext: Buffer): void;
      bytesRead: number;
      bytesWritten: number;
    };
    decrypt: {
      (out: Buffer, key: Buffer, nonce: Buffer, ad: Buffer, ciphertext: Buffer): void;
      bytesRead: number;
      bytesWritten: number;
    };
    rekey: {
      (out: Buffer, key: Buffer): void;
      bytesRead: number;
      bytesWritten: number;
    };
  }

  function createCipher(): CipherModule;
  export = createCipher;
}

declare module 'noise-protocol/cipher-state' {
  interface CipherStateModule {
    STATELEN: number;
    NONCELEN: number;
    MACLEN: number;
    initializeKey(state: Buffer, key: Buffer | null): void;
    hasKey(state: Buffer): boolean;
    setNonce(state: Buffer, nonce: Buffer): void;
    encryptWithAd: {
      (state: Buffer, out: Buffer, ad: Buffer, plaintext: Buffer): void;
      bytesRead: number;
      bytesWritten: number;
    };
    decryptWithAd: {
      (state: Buffer, out: Buffer, ad: Buffer, ciphertext: Buffer): void;
      bytesRead: number;
      bytesWritten: number;
    };
    rekey: {
      (state: Buffer): void;
      bytesRead: number;
      bytesWritten: number;
    };
  }

  function createCipherState(opts: { cipher: ReturnType<typeof import('noise-protocol/cipher')> }): CipherStateModule;
  export = createCipherState;
}
