package dev.vrmc.provider;

import java.lang.reflect.Constructor;
import java.lang.reflect.Method;
import java.lang.reflect.Modifier;

/**
 * Host test for the in-VR quick-menu injection contract.
 *
 * <p>The provider adds its "VRMC Quick Menu" button to the game menu through reflection because
 * {@code Screen.addRenderableWidget} is protected. A Minecraft update that renames or re-signatures
 * that method (or the {@code StringWidget} constructor) would compile fine and only fail on device,
 * where the whole feature silently disappears. Loading the real 26.2 classes here makes the suite
 * fail instead.
 */
public final class VisionQuickMenuReflectionTest {
    private static int checks;
    private static int failures;

    private static void check(String name, boolean ok) {
        checks++;
        if (!ok) failures++;
        System.out.println("  " + (ok ? "ok  " : "FAIL") + " " + name);
    }

    public static void main(String[] args) throws Exception {
        ClassLoader loader = VisionQuickMenuReflectionTest.class.getClassLoader();
        Class<?> screen = Class.forName("net.minecraft.client.gui.screens.Screen", false, loader);
        Class<?> listener = Class.forName(
            "net.minecraft.client.gui.components.events.GuiEventListener", false, loader);
        Method add = screen.getDeclaredMethod("addRenderableWidget", listener);
        check("Screen.addRenderableWidget(GuiEventListener) exists", add != null);
        check("it is protected, so the provider must use reflection + setAccessible",
            !Modifier.isPublic(add.getModifiers()));
        check("it is the single-argument overload the provider invokes", add.getParameterCount() == 1);

        Class<?> pause = Class.forName("net.minecraft.client.gui.screens.PauseScreen", false, loader);
        check("PauseScreen exists (the only screen the provider injects into)",
            pause.getName().endsWith("PauseScreen"));

        Class<?> widget = Class.forName("net.minecraft.client.gui.components.StringWidget", false, loader);
        Class<?> component = Class.forName("net.minecraft.network.chat.Component", false, loader);
        Class<?> font = Class.forName("net.minecraft.client.gui.Font", false, loader);
        Constructor<?> stringWidget = widget.getConstructor(
            int.class, int.class, int.class, int.class, component, font);
        check("StringWidget(int,int,int,int,Component,Font) still exists (menu labels)",
            stringWidget != null);

        System.out.println("[m5-quick-menu-reflection-test] " + checks + " checks, " + failures + " failed");
        System.out.println(failures == 0
            ? "[m5-quick-menu-reflection-test] PASS"
            : "[m5-quick-menu-reflection-test] FAIL");
        if (failures != 0) System.exit(1);
    }
}
