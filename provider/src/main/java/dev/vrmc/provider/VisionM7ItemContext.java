package dev.vrmc.provider;

/**
 * Fail-safe item-context probe for the M7 gesture engine (bow held / food or drink held).
 *
 * <p>The provider must not link against Minecraft item API details that are not part of the stable
 * compile surface (the {@code ItemStack} accessors currently pull in jspecify annotations that are
 * not on the provider build classpath, and an API drift must never crash a frame). This helper
 * therefore resolves everything reflectively once and degrades to "unknown / not held" on any
 * failure; the gesture engine's context flags are advisory and {@code m7.context=off} keeps the
 * geometry-only fallback available.
 */
final class VisionM7ItemContext {
    private static boolean attempted;
    private static boolean ready;
    private static java.lang.reflect.Method playerMainHand;
    private static java.lang.reflect.Method playerOffHand;
    private static java.lang.reflect.Method stackIsItem;
    private static java.lang.reflect.Method stackGetComponents;
    private static java.lang.reflect.Method mapHas;
    private static Object bowItem;
    private static Object foodComponent;
    private static Object consumableComponent;
    private static Class<?> resolvedPlayerClass;

    private VisionM7ItemContext() {}

    private static synchronized boolean init(Class<?> playerClass) {
        if (attempted && resolvedPlayerClass == playerClass) return ready;
        attempted = true;
        resolvedPlayerClass = playerClass;
        ready = false;
        try {
            Class<?> stackClass = Class.forName("net.minecraft.world.item.ItemStack");
            Class<?> itemClass = Class.forName("net.minecraft.world.item.Item");
            Class<?> mapClass = Class.forName("net.minecraft.core.component.DataComponentMap");
            Class<?> typeClass = Class.forName("net.minecraft.core.component.DataComponentType");
            Class<?> componentsClass = Class.forName("net.minecraft.core.component.DataComponents");
            Class<?> itemsClass = Class.forName("net.minecraft.world.item.Items");
            playerMainHand = playerClass.getMethod("getMainHandItem");
            playerOffHand = playerClass.getMethod("getOffhandItem");
            stackIsItem = stackClass.getMethod("is", itemClass);
            stackGetComponents = stackClass.getMethod("getComponents");
            mapHas = mapClass.getMethod("has", typeClass);
            bowItem = itemsClass.getField("BOW").get(null);
            foodComponent = componentsClass.getField("FOOD").get(null);
            consumableComponent = componentsClass.getField("CONSUMABLE").get(null);
            ready = bowItem != null && foodComponent != null && consumableComponent != null;
        } catch (Throwable t) {
            ready = false;
            System.out.println("[VRMC-M7][WARN] item-context probe unavailable (" + t
                + "); bow/eat context stays off (set m7.context=off for geometry-only fallback)");
        }
        return ready;
    }

    /** @return bit0 = bow held, bit1 = food/drink held; 0 when the probe is unavailable. */
    static int flags(Object player) {
        if (player == null) return 0;
        if (!init(player.getClass())) return 0;
        int out = 0;
        try {
            Object main = playerMainHand.invoke(player);
            Object off = playerOffHand.invoke(player);
            if (isBow(main) || isBow(off)) out |= 1;
            if (isEdible(main) || isEdible(off)) out |= 2;
        } catch (Throwable t) {
            return 0;
        }
        return out;
    }

    private static boolean isBow(Object stack) throws ReflectiveOperationException {
        if (stack == null) return false;
        return Boolean.TRUE.equals(stackIsItem.invoke(stack, bowItem));
    }

    private static boolean isEdible(Object stack) throws ReflectiveOperationException {
        if (stack == null) return false;
        Object map = stackGetComponents.invoke(stack);
        if (map == null) return false;
        return Boolean.TRUE.equals(mapHas.invoke(map, foodComponent))
            || Boolean.TRUE.equals(mapHas.invoke(map, consumableComponent));
    }
}
