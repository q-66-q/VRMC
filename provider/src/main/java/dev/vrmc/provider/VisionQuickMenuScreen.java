package dev.vrmc.provider;

import net.minecraft.client.gui.components.Button;
import net.minecraft.client.gui.components.StringWidget;
import net.minecraft.client.gui.screens.Screen;
import net.minecraft.network.chat.Component;

/**
 * In-VR quick menu: comfort and recovery controls reachable with the hands, without taking the
 * headset view back to the launcher window.
 *
 * <p>It is an ordinary Minecraft screen, so it is rendered on Vivecraft's in-world GUI panel and
 * operated exactly like every other menu (head-ray cursor + right pinch; left fist tap goes back).
 * Opened from the "VRMC Quick Menu" button the provider adds to the game menu, or by the
 * {@code quick-menu} launcher command.
 *
 * <p>Most actions apply immediately (recenter, height calibration, play style, turn step, world
 * scale, draw distance, release input). Settings the launcher also owns are persisted with
 * {@link VisionSettingsFile} so the launcher window shows the same value. The comfort vignette is
 * the exception: the compositor reads its flag file when the immersive space opens, so a vignette
 * change applies at the next immersive session and the menu says so.
 */
public final class VisionQuickMenuScreen extends Screen {
    /** Actions/state the menu needs from the provider (kept narrow so the screen stays dumb). */
    public interface Host {
        void quickRecenter();
        void quickCalibrateHeight();
        boolean quickSeatedPlay();
        void quickSetSeatedPlay(boolean seated);
        float quickTurnIncrement();
        void quickSetTurnIncrement(float degrees);
        /** 0 = off .. 3 = strong; -1 when the vignette file is not reachable. */
        int quickVignetteLevel();
        void quickSetVignetteLevel(int level);
        float quickWorldScale();
        void quickSetWorldScale(float scale);
        int quickRenderDistance();
        void quickSetRenderDistance(int chunks);
        void quickReleaseInput();
        String[] quickControlsHelp();
    }

    private static final String[] VIGNETTE_NAMES = {"Off", "Light", "Medium", "Strong"};
    private static final int BUTTON_W = 150;
    private static final int BUTTON_H = 20;
    private static final int GAP = 4;

    private final Host host;
    private final Screen parent;
    private final boolean guide;
    private String status = "";

    public VisionQuickMenuScreen(Host host, Screen parent) {
        this(host, parent, false);
    }

    private VisionQuickMenuScreen(Host host, Screen parent, boolean guide) {
        super(Component.literal(guide ? "VRMC Gesture Guide" : "VRMC Quick Menu"));
        this.host = host;
        this.parent = parent;
        this.guide = guide;
    }

    @Override
    protected void init() {
        if (this.guide) {
            initGuide();
        } else {
            initMenu();
        }
    }

    private void initMenu() {
        int cx = this.width / 2;
        int rows = 6;
        int blockH = rows * BUTTON_H + (rows - 1) * GAP;
        int top = Math.max(30, (this.height - blockH) / 2);
        int left = cx - BUTTON_W - GAP / 2;
        int right = cx + GAP / 2;
        addRenderableWidget(new StringWidget(cx - 150, top - 22, 300, 12, this.title, this.font));

        addRenderableWidget(Button.builder(Component.literal("Recenter view"), b -> {
            this.host.quickRecenter();
            setStatus("View recentered");
        }).bounds(left, top, BUTTON_W, BUTTON_H).build());
        addRenderableWidget(Button.builder(Component.literal("Calibrate height"), b -> {
            this.host.quickCalibrateHeight();
            setStatus("Height set from your current head position");
        }).bounds(right, top, BUTTON_W, BUTTON_H).build());

        int y = top + BUTTON_H + GAP;
        addRenderableWidget(Button.builder(playStyleLabel(), b -> {
            this.host.quickSetSeatedPlay(!this.host.quickSeatedPlay());
            b.setMessage(playStyleLabel());
            setStatus(this.host.quickSeatedPlay()
                ? "Seated: right middle-pinch tap = jump, hold = sneak; left = turn"
                : "Standing: rise = jump, crouch = sneak");
        }).bounds(left, y, BUTTON_W, BUTTON_H).build());
        addRenderableWidget(Button.builder(turnLabel(), b -> {
            this.host.quickSetTurnIncrement(VisionSettingsFile.nextTurnStep(this.host.quickTurnIncrement()));
            b.setMessage(turnLabel());
        }).bounds(right, y, BUTTON_W, BUTTON_H).build());

        y += BUTTON_H + GAP;
        Button vignette = Button.builder(vignetteLabel(), b -> {
            int level = this.host.quickVignetteLevel();
            if (level < 0) return;
            this.host.quickSetVignetteLevel((level + 1) % VIGNETTE_NAMES.length);
            b.setMessage(vignetteLabel());
            setStatus("Vignette saved; applies at the next immersive session");
        }).bounds(left, y, BUTTON_W, BUTTON_H).build();
        vignette.active = this.host.quickVignetteLevel() >= 0;
        addRenderableWidget(vignette);
        addRenderableWidget(Button.builder(worldScaleLabel(), b -> {
            this.host.quickSetWorldScale(VisionSettingsFile.nextWorldScale(this.host.quickWorldScale()));
            b.setMessage(worldScaleLabel());
            setStatus("World scale updated");
        }).bounds(right, y, BUTTON_W, BUTTON_H).build());

        y += BUTTON_H + GAP;
        addRenderableWidget(Button.builder(renderDistanceLabel(), b -> {
            this.host.quickSetRenderDistance(
                VisionSettingsFile.nextRenderDistance(this.host.quickRenderDistance()));
            b.setMessage(renderDistanceLabel());
            setStatus("Draw distance updated");
        }).bounds(left, y, BUTTON_W, BUTTON_H).build());
        addRenderableWidget(Button.builder(Component.literal("Release stuck input"), b -> {
            this.host.quickReleaseInput();
            setStatus("All held actions released");
        }).bounds(right, y, BUTTON_W, BUTTON_H).build());

        y += BUTTON_H + GAP;
        addRenderableWidget(Button.builder(Component.literal("Gesture guide"), b ->
            this.minecraft.gui.setScreen(new VisionQuickMenuScreen(this.host, this, true))
        ).bounds(left, y, BUTTON_W, BUTTON_H).build());
        addRenderableWidget(Button.builder(Component.literal("Back to game"), b ->
            this.minecraft.gui.setScreen(null)
        ).bounds(right, y, BUTTON_W, BUTTON_H).build());

        y += BUTTON_H + GAP;
        addRenderableWidget(Button.builder(Component.literal("Done"), b -> onClose())
            .bounds(cx - BUTTON_W / 2, y, BUTTON_W, BUTTON_H).build());
        addRenderableWidget(new StringWidget(cx - 200, y + BUTTON_H + 6, 400, 12,
            Component.literal(this.status), this.font));
    }

    private void initGuide() {
        int cx = this.width / 2;
        String[] lines = this.host.quickControlsHelp();
        int lineH = 11;
        int top = Math.max(22, (this.height - (lines.length * lineH + 40)) / 2);
        addRenderableWidget(new StringWidget(cx - 150, top - 16, 300, 12, this.title, this.font));
        int y = top;
        int textW = Math.min(this.width - 16, 420);
        for (String line : lines) {
            addRenderableWidget(new StringWidget(cx - textW / 2, y, textW, lineH,
                Component.literal(line), this.font));
            y += lineH;
        }
        addRenderableWidget(Button.builder(Component.literal("Back"), b -> onClose())
            .bounds(cx - BUTTON_W / 2, y + 8, BUTTON_W, BUTTON_H).build());
    }

    private void setStatus(String text) {
        this.status = text == null ? "" : text;
        rebuildWidgets();
    }

    private Component playStyleLabel() {
        return Component.literal("Play style: " + (this.host.quickSeatedPlay() ? "Seated" : "Standing"));
    }

    private Component turnLabel() {
        float degrees = this.host.quickTurnIncrement();
        return Component.literal(degrees <= 0.0F ? "Turning: Smooth"
            : "Turning: Snap " + Math.round(degrees) + "°");
    }

    private Component vignetteLabel() {
        int level = this.host.quickVignetteLevel();
        if (level < 0) return Component.literal("Comfort vignette: n/a");
        return Component.literal("Comfort vignette: "
            + VIGNETTE_NAMES[Math.min(level, VIGNETTE_NAMES.length - 1)]);
    }

    private Component worldScaleLabel() {
        return Component.literal("World scale: "
            + String.format(java.util.Locale.ROOT, "%.2fx", this.host.quickWorldScale()));
    }

    private Component renderDistanceLabel() {
        return Component.literal("Draw distance: " + this.host.quickRenderDistance() + " chunks");
    }

    @Override
    public void onClose() {
        this.minecraft.gui.setScreen(this.parent);
    }

    @Override
    public boolean isPauseScreen() {
        return true;
    }
}
