import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';

const DOMAIN = 0x0000;

type OrientationMode = 'portrait' | 'landscape' | 'auto';

export default class EntryAbility extends UIAbility {
  private applyPreferredOrientation(windowStage: window.WindowStage): void {
    const setting = Promise.resolve()
      .then((): Promise<preferences.Preferences> => preferences.getPreferences(this.context, 'settings'))
      .then(
        (prefs: preferences.Preferences): Promise<preferences.ValueType> => prefs.get('orientationMode', 'portrait'),
        (): Promise<preferences.ValueType> => Promise.resolve('portrait'),
      )
      .then(
        (value: preferences.ValueType): OrientationMode => {
          const s: string = typeof value === 'string' ? value : String(value);
          if (s === 'landscape' || s === 'auto') return s;
          return 'portrait';
        },
        (): OrientationMode => 'portrait',
      );

    const mainWindow = Promise.resolve().then((): Promise<window.Window> => windowStage.getMainWindow());

    Promise.all([setting, mainWindow]).then(
      (values: Array<OrientationMode | window.Window>): void => {
        const mode: OrientationMode = (values[0] as OrientationMode) ?? 'portrait';
        const w: window.Window = values[1] as window.Window;
        let orientation: window.Orientation;
        if (mode === 'landscape') {
          orientation = window.Orientation.LANDSCAPE;
        } else if (mode === 'auto') {
          orientation = window.Orientation.AUTO_ROTATION_RESTRICTED;
        } else {
          orientation = window.Orientation.PORTRAIT;
        }
        w.setPreferredOrientation(orientation).then(
          (): void => undefined,
          (err: Error | string): void => {
            hilog.error(DOMAIN, 'testTag', 'Failed to set preferred orientation. Cause: %{public}s', JSON.stringify(err));
          },
        );
      },
      (err: Error | string): void => {
        hilog.error(DOMAIN, 'testTag', 'Failed to prepare preferred orientation. Cause: %{public}s', JSON.stringify(err));
      },
    );
  }

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    const appContext = this.context.getApplicationContext();
    if (appContext) {
      Promise.resolve()
        .then((): void => appContext.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET))
        .then(
          (): void => undefined,
          (err: Error | string): void => {
            hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
          },
        );
    }
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    this.applyPreferredOrientation(windowStage);

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
    });
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}
