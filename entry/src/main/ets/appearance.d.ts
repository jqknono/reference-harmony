declare module '@ohos.appearance' {
  export enum ColorMode {
    LIGHT = 0,
    DARK = 1,
  }

  interface Appearance {
    getColorMode(): ColorMode;
    on(type: 'colorModeChange', callback: (mode: ColorMode) => void): void;
    off?(type: 'colorModeChange', callback?: (mode: ColorMode) => void): void;
    ColorMode: typeof ColorMode;
  }

  const appearance: Appearance;
  export default appearance;
}



