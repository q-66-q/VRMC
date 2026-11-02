package dev.vrmc.provider;

import org.joml.Matrix4f;
import org.joml.Matrix4fc;
import org.joml.Vector2f;
import org.joml.Vector3f;

/**
 * M4-W2 gaze geometry (pure Java/JOML; host-testable, no Minecraft/Vivecraft imports).
 *
 * <p>The compositor overlays a {@code grid_w x grid_h} grid of CompositorServices tracking areas on
 * the presented layer. The system highlights the area under the user's true gaze and tags an indirect
 * pinch with that area id; this class maps the tile id back to a grid cell, a drawable-NDC point, a
 * provider eye-space ray, and finally a point on Vivecraft's GUI plane (the same plane
 * {@code GuiHandler.getTexCoordsForCursor} uses for the hand cursor).
 *
 * <p>Conventions:
 * <ul>
 *   <li>tile (x=0,y=0) is the TOP-LEFT of the presented layer;</li>
 *   <li>layer NDC x∈[-1,1] left→right, y∈[-1,1] bottom→top (visionOS drawable convention);</li>
 *   <li>provider eye-space ray for a display-frustum point: x = (ndcX*(right-left)+(right+left))/2,
 *       y = (ndcY*(up-down)+(up+down))/2, z = -1 (tangents are signed: left/down negative);</li>
 *   <li>GUI plane math mirrors GuiHandler.getTexCoordsForCursor: plane normal = rotation*FORWARD,
 *       plane right = rotation*LEFT, plane up = rotation*UP, quad is 1 m x 1 m scaled by guiScale.</li>
 * </ul>
 * The real cross-language/display-view values come from the bridge; this class only does arithmetic
 * and is covered by VisionGazeMathTest with synthetic planes.
 */
public final class VisionGazeMath {
    private VisionGazeMath() {}

    /** Tile id is 1 + y*gridW + x (compositor contract). Returns null for an invalid id. */
    public static Vector2f tileToNdc(long tileId, int gridW, int gridH) {
        if (gridW <= 0 || gridH <= 0 || tileId <= 0) return null;
        long index = tileId - 1;
        if (index >= (long) gridW * gridH) return null;
        int x = (int) (index % gridW);
        int y = (int) (index / gridW);
        // Pixel/tile centre -> layer NDC.
        float ndcX = -1.0F + (2.0F * (x + 0.5F) / gridW);
        float ndcY = 1.0F - (2.0F * (y + 0.5F) / gridH);
        return new Vector2f(ndcX, ndcY);
    }

    /**
     * Ray from the provider eye through a drawable NDC point.
     *
     * @param tangents signed left,right,up,down frustum tangents (same order as display views)
     * @return normalized eye-space direction with z = -1 (forward)
     */
    public static Vector3f eyeRay(float[] tangents, Vector2f ndc) {
        return eyeRay(tangents[0], tangents[1], tangents[2], tangents[3], ndc);
    }

    public static Vector3f eyeRay(float left, float right, float up, float down, Vector2f ndc) {
        float x = (ndc.x * (right - left) + (right + left)) * 0.5F;
        float y = (ndc.y * (up - down) + (up + down)) * 0.5F;
        return new Vector3f(x, y, -1.0F).normalize();
    }

    /**
     * Intersect a room-space ray with the Vivecraft GUI plane and return GUI texture coordinates
     * (top-left anchored, exactly like GuiHandler.getTexCoordsForCursor).
     *
     * @param origin room/world-space ray origin
     * @param dir    room/world-space normalized ray direction
     * @param guiPos GUI centre in room space
     * @param guiRotation GUI orientation in room space
     * @param guiScale Vivecraft GUI scale
     * @param aspect  MC window scaledHeight/scaledWidth (GuiHandler uses this)
     * @return (u,v) in [0,1], or null when the ray misses/behind the plane or the result is non-finite
     */
    public static Vector2f intersectGuiPlane(Vector3f origin, Vector3f dir, Vector3f guiPos,
                                             Matrix4fc guiRotation, float guiScale, float aspect) {
        if (origin == null || dir == null || guiPos == null || guiRotation == null) return null;
        Vector3f normal = guiRotation.transformDirection(new Vector3f(0.0F, 0.0F, 1.0F));
        Vector3f right = guiRotation.transformDirection(new Vector3f(1.0F, 0.0F, 0.0F));
        Vector3f up = guiRotation.transformDirection(new Vector3f(0.0F, 1.0F, 0.0F));
        float denominator = normal.dot(dir);
        if (Math.abs(denominator) < 1.0E-5F) return null;
        Vector3f topLeft = new Vector3f(guiPos)
            .sub(up.mul(0.5F, new Vector3f()))
            .sub(right.mul(0.5F, new Vector3f()));
        float distance = -normal.dot(new Vector3f(origin).sub(topLeft)) / denominator;
        if (!(distance > 0.0F) || !Float.isFinite(distance)) return null;
        Vector3f point = new Vector3f(origin).add(new Vector3f(dir).mul(distance));
        point.sub(topLeft);
        float u = point.dot(right);
        float v = point.dot(up);
        u = (u - 0.5F) / 1.5F / guiScale + 0.5F;
        v = (v - 0.5F) / aspect / 1.5F / guiScale + 0.5F;
        v = 1.0F - v;
        if (!Float.isFinite(u) || !Float.isFinite(v) || u < 0.0F || u > 1.0F || v < 0.0F || v > 1.0F) {
            return null;
        }
        return new Vector2f(u, v);
    }

    /** Transform an eye-space direction/position through the eye-to-head transform and head pose. */
    public static Vector3f eyeToRoomDirection(Matrix4fc eyeToHead, Matrix4fc headPose, Vector3f eyeDir) {
        Vector3f headDir = new Matrix4f(eyeToHead).transformDirection(new Vector3f(eyeDir));
        return headPose.transformDirection(headDir);
    }

    public static Vector3f eyeOriginToRoom(Matrix4fc eyeToHead, Matrix4fc headPose) {
        Vector3f eyePos = new Vector3f(eyeToHead.m30(), eyeToHead.m31(), eyeToHead.m32());
        return headPose.transformPosition(eyePos);
    }
}
