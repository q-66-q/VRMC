package dev.vrmc.provider;

import org.joml.Matrix4f;
import org.joml.Vector2f;
import org.joml.Vector3f;

/** Host test for M4-W2 gaze geometry (tile -> NDC -> eye ray -> GUI plane UV). */
public final class VisionGazeMathTest {
    private static int checks;
    private static int failures;

    private static void check(String name, boolean ok, String detail) {
        checks++;
        if (!ok) { failures++; System.out.println("  FAIL " + name + " " + detail); }
    }

    public static void main(String[] args) {
        // Tile centre mapping: 32x18, tile (0,0) top-left, centre x≈-0.96875, y≈+0.9444.
        Vector2f topLeft = VisionGazeMath.tileToNdc(1, 32, 18);
        check("top-left tile centre", topLeft != null && Math.abs(topLeft.x + 0.96875F) < 1e-4F
            && Math.abs(topLeft.y - 0.9444F) < 1e-3F, String.valueOf(topLeft));
        Vector2f middle = VisionGazeMath.tileToNdc(1L + 9L * 32L + 16L, 32, 18); // x=16,y=9
        check("middle tile near centre", middle != null && Math.abs(middle.x) < 0.04F
            && Math.abs(middle.y) < 0.06F, String.valueOf(middle));
        check("invalid tile", VisionGazeMath.tileToNdc(0, 32, 18) == null
            && VisionGazeMath.tileToNdc(32L * 18L + 1, 32, 18) == null, "");

        // Signed device-like tangents: left=-1.732,right=1.0,up=1.0,down=-1.192.
        float[] tan = {-1.732F, 1.0F, 1.0F, -1.192F};
        Vector3f centreDir = VisionGazeMath.eyeRay(tan, new Vector2f(0.0F, 0.0F));
        check("centre ray finite/normalized", Float.isFinite(centreDir.x) && Float.isFinite(centreDir.y)
            && Math.abs(centreDir.length() - 1.0F) < 1e-5F, String.valueOf(centreDir));
        check("centre ray points forward", centreDir.z < -0.9F, String.valueOf(centreDir));

        // A ray straight ahead from the origin hits the centre of a GUI plane one metre in front.
        Matrix4f identityRot = new Matrix4f();
        Vector3f origin = new Vector3f(0.0F, 0.0F, 0.0F);
        Vector3f forward = new Vector3f(0.0F, 0.0F, 1.0F);
        Vector2f centreUv = VisionGazeMath.intersectGuiPlane(origin, forward,
            new Vector3f(0.0F, 0.0F, 1.0F), identityRot, 1.0F, 16.0F / 9.0F);
        check("gui plane centre hit", centreUv != null && Math.abs(centreUv.x - 0.5F) < 1e-4F
            && Math.abs(centreUv.y - 0.5F) < 1e-4F, String.valueOf(centreUv));

        // Off-axis ray hits a different GUI coordinate.
        Vector3f off = new Vector3f(0.2F, 0.0F, 1.0F).normalize();
        Vector2f offUv = VisionGazeMath.intersectGuiPlane(origin, off,
            new Vector3f(0.0F, 0.0F, 1.0F), identityRot, 1.0F, 16.0F / 9.0F);
        check("off-axis differs", offUv != null && offUv.x > centreUv.x + 0.03F, String.valueOf(offUv));

        // Behind / parallel rays miss.
        check("behind miss", VisionGazeMath.intersectGuiPlane(origin, new Vector3f(0, 0, -1),
            new Vector3f(0, 0, 1), identityRot, 1.0F, 1.0F) == null, "");
        check("parallel miss", VisionGazeMath.intersectGuiPlane(new Vector3f(1, 0, 0), forward,
            new Vector3f(0, 0, 1), identityRot, 1.0F, 1.0F) == null, "");

        // Eye-to-head + head transform: identity keeps the direction.
        Matrix4f eyeToHead = new Matrix4f().translate(0.03F, 0.0F, -0.04F);
        Matrix4f head = new Matrix4f();
        Vector3f roomDir = VisionGazeMath.eyeToRoomDirection(eyeToHead, head, new Vector3f(0, 0, -1));
        check("identity eye/head direction", Math.abs(roomDir.z + 1.0F) < 1e-5F, String.valueOf(roomDir));
        Vector3f roomOrigin = VisionGazeMath.eyeOriginToRoom(eyeToHead, head);
        check("eye origin transform", Math.abs(roomOrigin.x - 0.03F) < 1e-6F
            && Math.abs(roomOrigin.z + 0.04F) < 1e-6F, String.valueOf(roomOrigin));

        System.out.println("[m4-gaze-test] " + checks + " checks, " + failures + " failed");
        System.out.println(failures == 0 ? "[m4-gaze-test] PASS" : "[m4-gaze-test] FAIL");
        if (failures != 0) System.exit(1);
    }
}
