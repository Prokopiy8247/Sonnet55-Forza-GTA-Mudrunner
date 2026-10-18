namespace MudRunner.Audio.Dsp
{
    /// <summary>Pre-rendered one-shot sounds (generated procedurally at startup by <see cref="SfxBank"/>).</summary>
    public enum Sfx
    {
        BumpThump = 0, SuspClonk, MetalThud, PlasticThud, CargoClank, RockThud, WoodThunk, VehicleCrunch,
        MudSplashSmall, MudSplashBig, WaterSplashSmall, WaterSplashBig,
        ShiftClunkLight, ShiftClunkHeavy, GearGrind, HandbrakeRatchet, AirPsstOn, AirPsstOff, TurboBlowOff,
        HookClunk, HookRelease, RopeTwang, StarterClunk,
        UiNotify, UiWarn, UiStuck, UiFuel, UiClick, UiSuccess,
        Count
    }
}
