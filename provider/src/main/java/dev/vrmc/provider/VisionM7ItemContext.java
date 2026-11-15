package dev.vrmc.provider;

/**
 * Fail-safe item-context probe for the M7 gesture engine (bow held / food or drink held / block held).
 *
 * <p>The provider must not link against Minecraft item API details that are not part of the stable
 * compile surface. This helper resolves everything reflectively once and degrades to "unknown / not
 * held" on any failure; the gesture engine's context flags are advisory and {@code m7.context=off}
 * keeps the geometry-only fallback available.
 */
final class VisionM7ItemContext {
    private static boolean attempted;
    private static boolean ready;
    private static Class<?> resolvedPlayerClass;
    private static java.lang.reflect.Method playerMainHand;
    private static java.lang.reflect.Method playerOffHand;
    private static java.lang.reflect.Method stackGetItem;
    private static java.lang.reflect.Method stackGetComponents;
    private static java.lang.reflect.Method mapHas;
    private static Class<?> blockItemClass;
    private static Object bowItem;
    private static Object foodComponent;
    private static Object consumableComponent;
    private static boolean componentsReady;

    /** bit0 = bow held, bit1 = food/drink held, bit2 = block item in main hand. */
    static int flags(Object player) {
        if (player == null) return 0;
        if (!init(player.getClass())) return 0;
        int out = 0;
        try {
            Object main = playerMainHand.invoke(player);
            Object off = playerOffHand.invoke(player);
            if (isBow(main) || isBow(off)) out |= 1;
            if (componentsReady && (isEdible(main) || isEdible(off))) out |= 2;
            if (isBlock(main)) out |= 4;
        } catch (Throwable t) {
            return 0;   // degrade to "no context" for this frame; the engine falls back to geometry
        }
        return out;
    }

    /**
     * Resolves the reflective handles once per concrete player class (Method handles are tied to the
     * class they were looked up on). A failed probe is not retried for the same class, so a missing
     * API costs one warning line instead of one per frame.
     */
    private static synchronized boolean init(Class<?> playerClass) {
        if (attempted && resolvedPlayerClass == playerClass) return ready;
        attempted = true;
        resolvedPlayerClass = playerClass;
        ready = false;
        componentsReady = false;
        try {
            Class<?> stackClass = Class.forName("net.minecraft.world.item.ItemStack");
            Class<?> itemsClass = Class.forName("net.minecraft.world.item.Items");
            blockItemClass = Class.forName("net.minecraft.world.item.BlockItem");
            playerMainHand = playerClass.getMethod("getMainHandItem");
            playerOffHand = playerClass.getMethod("getOffhandItem");
            stackGetItem = stackClass.getMethod("getItem");
            bowItem = itemsClass.getField("BOW").get(null);
            try {
                Class<?> mapClass = Class.forName("net.minecraft.core.component.DataComponentMap");
                Class<?> typeClass = Class.forName("net.minecraft.core.component.DataComponentType");
                Class<?> componentsClass = Class.forName("net.minecraft.core.component.DataComponents");
                stackGetComponents = stackClass.getMethod("getComponents");
                mapHas = mapClass.getMethod("has", typeClass);
                foodComponent = componentsClass.getField("FOOD").get(null);
                consumableComponent = componentsClass.getField("CONSUMABLE").get(null);
                componentsReady = foodComponent != null || consumableComponent != null;
            } catch (Throwable t) {
                System.out.println("[VRMC-M7][WARN] food/bow component probe unavailable (" + t
                    + "); food context stays off (block/bow geometry fallback remains)");
            }
            ready = blockItemClass != null && stackGetItem != null && playerMainHand != null;
            if (!ready) {
                System.out.println("[VRMC-M7][WARN] item-context probe unavailable; context falls back");
            }
        } catch (Throwable t) {
            ready = false;
            System.out.println("[VRMC-M7][WARN] item-context probe unavailable (" + t
                + "); bow/eat/block context stays off (set m7.context=off for geometry-only fallback)");
        }
        return ready;
    }

    private static Object item(Object stack) throws ReflectiveOperationException {
        return stack == null ? null : stackGetItem.invoke(stack);
    }

    /** {@code Items.BOW} is a registry singleton, so identity is exact (crossbows are deliberately excluded). */
    private static boolean isBow(Object stack) throws ReflectiveOperationException {
        Object item = item(stack);
        return item != null && item == bowItem;
    }

    private static java.lang.reflect.Method playerGetProjectile;
    private static boolean projectileAttempted;

    /** True when {@code stack} is the vanilla bow (same identity check as the bow-hand mask). */
    static boolean isBowStack(Object player, Object stack) {
        if (player == null || stack == null || !init(player.getClass())) return false;
        try {
            return isBow(stack);
        } catch (Throwable t) {
            return false;
        }
    }

    /** The player's main-hand stack (null when unavailable). */
    static Object mainHandStack(Object player) {
        if (player == null || !init(player.getClass())) return null;
        try {
            return playerMainHand.invoke(player);
        } catch (Throwable t) {
            return null;
        }
    }

    /** The ammunition {@code weapon} would shoot (vanilla Player.getProjectile; null when none/unavailable). */
    static Object projectileFor(Object player, Object weapon) {
        if (player == null || weapon == null || !init(player.getClass())) return null;
        try {
            if (!projectileAttempted) {
                projectileAttempted = true;
                for (Class<?> c = player.getClass(); c != null && playerGetProjectile == null; c = c.getSuperclass()) {
                    for (java.lang.reflect.Method m : c.getDeclaredMethods()) {
                        if (m.getName().equals("getProjectile") && m.getParameterCount() == 1
                            && m.getParameterTypes()[0].isInstance(weapon)) {
                            m.setAccessible(true);
                            playerGetProjectile = m;
                            break;
                        }
                    }
                }
            }
            return playerGetProjectile == null ? null : playerGetProjectile.invoke(player, weapon);
        } catch (Throwable t) {
            return null;
        }
    }

    /** 1 = bow in main hand, 2 = bow in off hand, 3 = both (bitmask used for bow render roll). */
    static int bowHands(Object player) {
        if (player == null || !init(player.getClass())) return 0;
        try {
            int mask = 0;
            if (isBow(playerMainHand.invoke(player))) mask |= 1;
            if (isBow(playerOffHand.invoke(player))) mask |= 2;
            return mask;
        } catch (Throwable t) {
            return 0;
        }
    }

    private static boolean isBlock(Object stack) throws ReflectiveOperationException {
        Object item = item(stack);
        return item != null && blockItemClass != null && blockItemClass.isInstance(item);
    }

    /** FOOD marks edible items; CONSUMABLE also covers drinks (potions, milk), which use the same mouth gesture. */
    private static boolean isEdible(Object stack) throws ReflectiveOperationException {
        if (!componentsReady || stack == null) return false;
        Object map = stackGetComponents.invoke(stack);
        if (map == null) return false;
        return (foodComponent != null && Boolean.TRUE.equals(mapHas.invoke(map, foodComponent)))
            || (consumableComponent != null && Boolean.TRUE.equals(mapHas.invoke(map, consumableComponent)));
    }
}
