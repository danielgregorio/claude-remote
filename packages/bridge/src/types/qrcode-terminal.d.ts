declare module 'qrcode-terminal' {
  interface Options {
    small?: boolean;
  }
  function generate(text: string, opts?: Options, callback?: (code: string) => void): void;
  export default { generate };
}
