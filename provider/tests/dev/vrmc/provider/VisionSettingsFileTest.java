package dev.vrmc.provider;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;

/** Host test for the quick-menu settings persistence helper. */
public final class VisionSettingsFileTest {
    private static int checks;
    private static int failures;

    private static void check(String name, boolean ok) {
        checks++;
        if (!ok) failures++;
        System.out.println("  " + (ok ? "ok  " : "FAIL") + " " + name);
    }

    public static void main(String[] args) throws Exception {
        Path dir = Files.createTempDirectory("vrmc-settings-file-test");
        Path file = dir.resolve("nested").resolve(VisionSettingsFile.RUNTIME_FILE);

        check("creates the file and parent directory", VisionSettingsFile.update(file, "comfort.seated", "true"));
        check("new file holds the key", Files.readAllLines(file).equals(List.of("comfort.seated=true")));

        Files.writeString(file, "# VRMC runtime settings\ncomfort.seated=false\nperformance.preset=quality\n"
            + "  comfort.seated = true\n! other comment\ncustom.key=keep me\n");
        check("update succeeds on an existing file", VisionSettingsFile.update(file, "comfort.seated", "true"));
        List<String> lines = Files.readAllLines(file);
        check("comments and unknown keys preserved in order", lines.equals(List.of(
            "# VRMC runtime settings", "comfort.seated=true", "performance.preset=quality",
            "! other comment", "custom.key=keep me")));
        check("duplicate definitions collapsed to one",
            lines.stream().filter(l -> l.trim().startsWith("comfort.seated")).count() == 1);

        check("appends a missing key", VisionSettingsFile.update(file, "comfort.worldRotationIncrement", "45"));
        check("appended key is last", Files.readAllLines(file).get(5).equals("comfort.worldRotationIncrement=45"));
        check("no temp file left behind", !Files.exists(file.resolveSibling(file.getFileName() + ".tmp")));

        VisionRuntimeSettings parsed = VisionRuntimeSettings.load(file.getParent().toFile(), s -> { });
        check("result parses as runtime settings (seated=true)", parsed.hasSeated && parsed.seated);

        String before = Files.readString(file);
        check("rejects a newline in the value", !VisionSettingsFile.update(file, "k", "a\nb=c"));
        check("rejects '=' in the key", !VisionSettingsFile.update(file, "a=b", "c"));
        check("rejects a blank key", !VisionSettingsFile.update(file, " ", "c"));
        check("rejects null arguments", !VisionSettingsFile.update(null, "k", "v")
            && !VisionSettingsFile.update(file, null, "v") && !VisionSettingsFile.update(file, "k", null));
        check("rejected updates leave the file untouched", Files.readString(file).equals(before));

        check("turn steps cycle 30 -> 45 -> 90 -> smooth -> 30",
            VisionSettingsFile.nextTurnStep(30.0F) == 45.0F && VisionSettingsFile.nextTurnStep(45.0F) == 90.0F
                && VisionSettingsFile.nextTurnStep(90.0F) == 0.0F && VisionSettingsFile.nextTurnStep(0.0F) == 30.0F);
        check("off-grid turn value snaps to the nearest step first",
            VisionSettingsFile.nextTurnStep(40.0F) == 90.0F && VisionSettingsFile.nextTurnStep(80.0F) == 0.0F);
        check("non-finite turn value is safe", VisionSettingsFile.nextTurnStep(Float.NaN) == 30.0F);

        check("render-distance steps cycle and snap to the nearest step",
            VisionSettingsFile.nextRenderDistance(6) == 8
                && VisionSettingsFile.nextRenderDistance(12) == 16
                && VisionSettingsFile.nextRenderDistance(24) == 6
                && VisionSettingsFile.nextRenderDistance(11) == 16
                && VisionSettingsFile.nextRenderDistance(30) == 6);

        check("world-scale steps cycle and snap to the nearest step",
            VisionSettingsFile.nextWorldScale(0.80F) == 0.90F
                && VisionSettingsFile.nextWorldScale(1.00F) == 1.10F
                && VisionSettingsFile.nextWorldScale(1.50F) == 0.80F
                && VisionSettingsFile.nextWorldScale(1.04F) == 1.10F
                && VisionSettingsFile.nextWorldScale(Float.NaN) == 0.80F);

        check("vignette: missing/zero/garbage = off", VisionSettingsFile.vignetteLevel(null) == 0
            && VisionSettingsFile.vignetteLevel("0") == 0 && VisionSettingsFile.vignetteLevel("abc") == 0
            && VisionSettingsFile.vignetteLevel("NaN") == 0);
        check("vignette: empty legacy flag = medium", VisionSettingsFile.vignetteLevel("") == 2);
        check("vignette: strengths map to the nearest level", VisionSettingsFile.vignetteLevel("0.30") == 1
            && VisionSettingsFile.vignetteLevel("0.50\n") == 2 && VisionSettingsFile.vignetteLevel("0.9") == 3
            && VisionSettingsFile.vignetteLevel("0.1") == 1);

        Path documents = dir.resolve("Documents");
        Path game = documents.resolve("instances").resolve("default");
        check("vignette flag resolves next to instances/", documents.resolve("vrmc-vignette.flag")
            .toAbsolutePath().normalize().equals(VisionSettingsFile.vignetteFlag(game)));
        check("vignette flag refuses other layouts", VisionSettingsFile.vignetteFlag(dir.resolve("run")) == null
            && VisionSettingsFile.vignetteFlag(null) == null);

        System.out.println("[m5-settings-file-test] " + checks + " checks, " + failures + " failed");
        System.out.println(failures == 0 ? "[m5-settings-file-test] PASS" : "[m5-settings-file-test] FAIL");
        if (failures != 0) System.exit(1);
    }
}
