package dev.vrmc.provider;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Map;

/**
 * Host unit test for the M4-W1 gesture engine {@link VisionInput} (no game instance, pure Java).
 *
 * <p>Covers design §5.3/§5.4 and the G4 safety minimum: pinch/fist hysteresis, released-state
 * arming, fist-tap single fire + re-arm, both-fist inventory tap, per-hand tracking-loss release,
 * stale-input release, malformed snapshot fail-safe, action-set gating, binding-table coverage,
 * per-hand origins and the tuning overrides. Run by provider/tests/run_tests.sh.
 */
public final class VisionInputTest {
    private static final long MS = 1_000_000L;
    private static final long T0 = 1_000_000_000L;
    private static final int LEFT = VisionInput.HAND_LEFT;
    private static final int RIGHT = VisionInput.HAND_RIGHT;
    private static final int[] FINGER_TIPS = {
        VisionInput.JOINT_INDEX_TIP, VisionInput.JOINT_MIDDLE_TIP,
        VisionInput.JOINT_RING_TIP, VisionInput.JOINT_LITTLE_TIP};
    private static final float PALM = 0.09F;
    private static final float OPEN_PINCH = 0.068F;
    private static final float OPEN_FIST = 1.79F;
    private static final float FIST = 0.9809F;
    private static final float PINCHED = 0.005F;

    private static int failures;
    private static int checks;

    public static void main(String[] args) {
        System.out.println("[m4-input-test] VisionInput gesture engine (pure Java; host unit test)");
        try {
            parseAndAcquisitionArming();
            pinchHysteresis();
            fistHysteresis();
            noPressWhileUnarmedAndRearmAfterLoss();
            fistTapSingleFireAndRearm();
            fistHoldUseBinding();
            bowTeleportSuppression();
            bothFistChordSuppressesContinuousUse();
            bothFistInventoryTap();
            bothFistChordPriority();
            trackingLossReleasesSameFrame();
            staleInputReleasesEverything();
            malformedInputsFailSafe();
            actionSetGating();
            bindingTableCoverage();
            tuningOverrides();
            tuningSummary();
        } catch (Throwable t) {
            t.printStackTrace();
            failures++;
        }
        System.out.println();
        System.out.printf("[m4-input-test] %d checks, %d failed%n", checks, failures);
        System.out.println(failures == 0 ? "[m4-input-test] PASS" : "[m4-input-test] FAIL");
        System.exit(failures == 0 ? 0 : 1);
    }

    // ------------------------------------------------------------------------------------------
    // 1. snapshot parsing + honest acquisition safety
    // ------------------------------------------------------------------------------------------
    private static void parseAndAcquisitionArming() {
        section("parse + acquisition arming (never boot a stuck press)");
        VisionInput in = new VisionInput();
        // Contract-snapshot-like frame: right hand pinching AND fisting on the acquisition frame,
        // left hand relaxed open. Raw detectors must see both right gestures, but nothing may press.
        in.poll(snapshot(8, 1960000000L, true, true, PINCHED, FIST, OPEN_PINCH, OPEN_FIST), 0, T0);
        check("frame_index parsed", in.frameIndex() == 8);
        check("valid_mask parsed", in.validMask() == 3);
        check("snapshot timestamp parsed", in.snapshotTimestampNs() == 1960000000L);
        check("left hand tracked", in.isHandTracked(LEFT));
        check("right hand tracked", in.isHandTracked(RIGHT));
        check("left chirality == 0", in.chirality(LEFT) == 0);
        check("right chirality == 1", in.chirality(RIGHT) == 1);
        check("left wrist x < 0", in.wristX(LEFT) < 0.0F);
        check("right wrist x > 0", in.wristX(RIGHT) > 0.0F);
        checkClose("right pinch distance", in.pinchDistance(RIGHT), PINCHED, 1.0E-4F);
        checkClose("right fist ratio", in.fistRatio(RIGHT), FIST, 1.0E-4F);
        checkClose("left pinch distance", in.pinchDistance(LEFT), OPEN_PINCH, 1.0E-4F);
        checkClose("left fist ratio", in.fistRatio(LEFT), OPEN_FIST, 1.0E-4F);
        check("right pinch raw detected", in.pinchRaw(RIGHT));
        check("right fist raw detected", in.fistRaw(RIGHT));
        check("left pinch raw not detected", !in.pinchRaw(LEFT));
        check("left fist raw not detected", !in.fistRaw(LEFT));
        check("SAFETY: acquisition frame never presses pinch", !in.pinchPressed(RIGHT));
        check("SAFETY: acquisition frame never presses fist", !in.fistPressed(RIGHT));
        check("acquisition frame never fires a fist tap", !in.fistTapPressed(RIGHT));
        check("no both-fist tap at acquisition", !in.bothFistTapPressed());
        check("healthy snapshot", in.isInputHealthy() && !in.isStale());
    }

    // ------------------------------------------------------------------------------------------
    // 2. pinch hysteresis (design: press < 0.030, release > 0.045, hold in between)
    // ------------------------------------------------------------------------------------------
    private static void pinchHysteresis() {
        section("pinch hysteresis (on 0.030 / off 0.045)");
        Rig rig = new Rig();
        rig.poll();                 // t=0 acquisition, open
        rig.pollMs(150);            // arms after 100 ms of continuous release
        check("open hand does not press", !rig.in.pinchPressed(RIGHT));
        rig.rPinch = 0.035F;        // between on and off, still released -> stays released
        rig.pollMs(10);
        check("0.035 between thresholds from released stays released", !rig.in.pinchRaw(RIGHT));
        rig.rPinch = 0.029F;        // < on -> press
        rig.pollMs(10);
        check("0.029 < pinchOn presses", rig.in.pinchRaw(RIGHT) && rig.in.pinchPressed(RIGHT));
        rig.rPinch = 0.044F;        // < off -> hold (hysteresis)
        rig.pollMs(10);
        check("0.044 holds the press", rig.in.pinchPressed(RIGHT));
        rig.rPinch = 0.045F;        // exactly off: contract releases only when > off
        rig.pollMs(10);
        check("0.045 exactly off still holds", rig.in.pinchPressed(RIGHT));
        rig.rPinch = 0.046F;        // > off -> release
        rig.pollMs(10);
        check("0.046 > pinchOff releases", !rig.in.pinchRaw(RIGHT) && !rig.in.pinchPressed(RIGHT));
        rig.rPinch = 0.031F;        // from released, 0.031 > on -> no press (hysteresis floor)
        rig.pollMs(10);
        check("0.031 from released does not press", !rig.in.pinchPressed(RIGHT));
        rig.rPinch = 0.020F;
        rig.pollMs(10);
        check("already-armed source presses immediately on a valid pinch", rig.in.pinchPressed(RIGHT));
    }

    // ------------------------------------------------------------------------------------------
    // 3. fist ratio hysteresis (on 1.25 / off 1.55)
    // ------------------------------------------------------------------------------------------
    private static void fistHysteresis() {
        section("fist hysteresis (on 1.25 / off 1.55)");
        Rig rig = new Rig();
        rig.poll();
        rig.pollMs(150);
        check("open hand is not a fist", !rig.in.fistRaw(RIGHT));
        rig.rFist = 1.30F;          // between, from released -> stays released
        rig.pollMs(10);
        check("1.30 between thresholds from released stays released", !rig.in.fistRaw(RIGHT));
        rig.rFist = 1.20F;          // < on -> press
        rig.pollMs(10);
        check("1.20 < fistOn engages", rig.in.fistRaw(RIGHT) && rig.in.fistPressed(RIGHT));
        rig.rFist = 1.50F;          // <= off -> hold
        rig.pollMs(10);
        check("1.50 holds the fist", rig.in.fistPressed(RIGHT));
        rig.rFist = 1.55F;          // exactly off -> still hold
        rig.pollMs(10);
        check("1.55 exactly off still holds", rig.in.fistPressed(RIGHT));
        rig.rFist = 1.56F;          // > off -> release
        rig.pollMs(10);
        check("1.56 > fistOff releases", !rig.in.fistRaw(RIGHT) && !rig.in.fistPressed(RIGHT));
    }

    // ------------------------------------------------------------------------------------------
    // 4. released-state arming: ignore a press until 100 ms of continuous release; re-arm on loss
    // ------------------------------------------------------------------------------------------
    private static void noPressWhileUnarmedAndRearmAfterLoss() {
        section("released-state arming (100 ms) and re-arm after tracking loss");
        Rig rig = new Rig();
        rig.rPinch = PINCHED;
        rig.poll();                 // acquisition with the hand already pinched
        check("press on acquisition frame is ignored", !rig.in.pinchPressed(RIGHT));
        rig.pollMs(10);
        rig.pollMs(10);
        check("holding the pinch while unarmed still ignores it", !rig.in.pinchPressed(RIGHT));
        rig.rPinch = OPEN_PINCH;
        rig.pollMs(10);
        check("opening releases", !rig.in.pinchPressed(RIGHT));
        rig.rPinch = PINCHED;
        rig.pollMs(50);             // 50 ms of release only -> still unarmed
        check("press after 50 ms release is ignored", !rig.in.pinchPressed(RIGHT));
        rig.rPinch = OPEN_PINCH;
        rig.pollMs(10);
        rig.pollMs(100);            // release run restarted, now 100 ms -> armed
        rig.rPinch = PINCHED;
        rig.pollMs(10);
        check("press after 100 ms continuous release is accepted", rig.in.pinchPressed(RIGHT));

        // tracking loss mid-press releases immediately and a re-acquired hand starts unarmed
        rig.rightTracked = false;
        rig.pollMs(10);
        check("tracking loss releases the press the same frame", !rig.in.pinchPressed(RIGHT));
        check("tracking loss clears raw state", !rig.in.pinchRaw(RIGHT));
        rig.rightTracked = true;
        rig.pollMs(10);
        check("re-acquired pinching hand does not press", !rig.in.pinchPressed(RIGHT));
        rig.pollMs(100);
        check("still held while re-arming -> no press", !rig.in.pinchPressed(RIGHT));
        rig.rPinch = OPEN_PINCH;
        rig.pollMs(10);
        rig.pollMs(100);
        rig.rPinch = PINCHED;
        rig.pollMs(10);
        check("armed after a fresh 100 ms release, press accepted", rig.in.pinchPressed(RIGHT));
    }

    // ------------------------------------------------------------------------------------------
    // 4b. W4 bow/use hold: right fist hold binds key.use continuously (GUI right click stays tap)
    // ------------------------------------------------------------------------------------------
    private static void fistHoldUseBinding() {
        section("W4 use hold: right fist hold drives key.use (bow draw/release)");
        Rig rig = new Rig();
        rig.poll();
        rig.pollMs(150);
        rig.in.setEnvironment(false, false, false);
        rig.rFist = FIST;
        rig.pollMs(16);
        check("right fist hold presses key.use", rig.in.actionPressed(VisionInput.KEY_USE));
        rig.pollMs(500);
        check("use remains held while fist stays closed", rig.in.actionPressed(VisionInput.KEY_USE));
        rig.rFist = OPEN_FIST;
        rig.pollMs(16);
        check("opening the fist releases key.use", !rig.in.actionPressed(VisionInput.KEY_USE));
        check("GUI right-click binding remains a fist tap (inactive in game set)",
            !rig.in.actionPressed("vivecraft.key.guiRightClick"));
    }

    // ------------------------------------------------------------------------------------------
    // 4c. W4 two-hand safety: right fist (bow/use hold) suppresses teleport from left pinch.
    // ------------------------------------------------------------------------------------------
    private static void bowTeleportSuppression() {
        section("W4 bow/use safety: right fist suppresses teleport");
        Rig rig = new Rig();
        rig.poll();
        rig.pollMs(150);
        rig.in.setEnvironment(false, false, false);
        rig.rFist = FIST;
        rig.pollMs(16);                 // right fist held (use)
        rig.lPinch = PINCHED;
        rig.pollMs(150);                // left pinch armed and pressed
        check("left pinch is pressed", rig.in.pinchPressed(LEFT));
        check("teleport suppressed while right fist held", !rig.in.actionPressed(VisionInput.KEY_TELEPORT));
        rig.rFist = OPEN_FIST;
        rig.pollMs(16);
        check("teleport returns after releasing the fist", rig.in.actionPressed(VisionInput.KEY_TELEPORT));
    }

    // ------------------------------------------------------------------------------------------
    // 4d. W4 conflict: both fists (inventory chord) must not also hold continuous use.
    // ------------------------------------------------------------------------------------------
    private static void bothFistChordSuppressesContinuousUse() {
        section("W4 conflict: both-fist inventory chord suppresses continuous use");
        Rig rig = new Rig();
        rig.poll(); rig.pollMs(150);
        rig.in.setEnvironment(false, false, false);
        rig.rFist = FIST;
        rig.pollMs(16);
        check("single right fist holds key.use", rig.in.actionPressed(VisionInput.KEY_USE));
        rig.lFist = FIST;
        rig.pollMs(16);
        check("both fists (inventory chord) suppresses key.use", !rig.in.actionPressed(VisionInput.KEY_USE));
        rig.pollMs(500);
        check("inventory tap still fires on the chord", rig.in.actionPressed(VisionInput.KEY_INVENTORY));
        rig.lFist = OPEN_FIST;
        rig.pollMs(16);
        check("use returns when the other fist opens", rig.in.actionPressed(VisionInput.KEY_USE));
    }

    // ------------------------------------------------------------------------------------------
    // 5. fist tap: one 2-frame pulse per hold, re-armed only on fist release
    // ------------------------------------------------------------------------------------------
    private static void fistTapSingleFireAndRearm() {
        section("fist tap: one 2-frame pulse per hold, re-arm on release");
        Rig rig = new Rig();
        rig.poll();
        rig.pollMs(150);            // armed
        rig.rFist = FIST;
        rig.pollMs(150);            // press onset (t=300)
        check("fist pressed", rig.in.fistPressed(RIGHT));
        List<Boolean> trace = new ArrayList<>();
        trace.add(rig.in.fistTapPressed(RIGHT)); // onset frame, never a tap
        for (int i = 0; i < 8; i++) { // t=450..1350; crosses the 400 ms hold at t=750
            rig.pollMs(150);
            trace.add(rig.in.fistTapPressed(RIGHT));
        }
        check("tap fires once the hold reaches 400 ms", countRising(trace) == 1
            && trace.get(3) && !trace.get(2));
        check("tap pulse is exactly 2 frames wide", firstPulseWidth(trace) == 2);
        check("holding longer does not re-fire", !anyTrue(trace, 5, trace.size()));

        rig.rFist = OPEN_FIST;      // release re-arms the tap
        rig.pollMs(150);
        check("release ends the fist", !rig.in.fistPressed(RIGHT));
        rig.rFist = FIST;
        rig.pollMs(150);            // second hold onset
        List<Boolean> second = new ArrayList<>();
        second.add(rig.in.fistTapPressed(RIGHT));
        for (int i = 0; i < 4; i++) {
            rig.pollMs(150);
            second.add(rig.in.fistTapPressed(RIGHT));
        }
        check("second hold fires exactly one pulse", countRising(second) == 1);
        check("second pulse is exactly 2 frames wide", firstPulseWidth(second) == 2);
        rig.rFist = OPEN_FIST;
        rig.pollMs(150);
        rig.rFist = FIST;
        rig.pollMs(150);
        List<Boolean> third = new ArrayList<>();
        third.add(rig.in.fistTapPressed(RIGHT));
        for (int i = 0; i < 4; i++) {
            rig.pollMs(150);
            third.add(rig.in.fistTapPressed(RIGHT));
        }
        check("each hold fires exactly one pulse (3 holds -> 3 pulses)",
            countRising(trace) + countRising(second) + countRising(third) == 3);
        check("every pulse is exactly 2 frames wide",
            firstPulseWidth(third) == 2 && countTrue(trace) == 2 && countTrue(second) == 2
                && countTrue(third) == 2);
    }

    // ------------------------------------------------------------------------------------------
    // 6. both-fist tap -> key.inventory, once per both-fist gesture
    // ------------------------------------------------------------------------------------------
    private static void bothFistInventoryTap() {
        section("both-fist tap (key.inventory): one 2-frame pulse per gesture");
        Rig rig = new Rig();
        rig.poll();
        rig.pollMs(150);
        rig.lFist = FIST;
        rig.rFist = FIST;
        rig.pollMs(150);            // both fists onset
        check("both fists engaged", rig.in.fistPressed(LEFT) && rig.in.fistPressed(RIGHT));
        List<Boolean> pulses = new ArrayList<>();
        pulses.add(rig.in.bothFistTapPressed());
        for (int i = 0; i < 3; i++) {
            rig.pollMs(150);
            pulses.add(rig.in.bothFistTapPressed());
        }
        check("both-fist tap fires after 400 ms", pulses.get(3));
        check("chord suppresses the per-hand tap pulses during the hold",
            !rig.in.fistTapPressed(LEFT) && !rig.in.fistTapPressed(RIGHT));
        rig.pollMs(150);
        check("both-fist pulse second frame", rig.in.bothFistTapPressed());
        rig.pollMs(150);
        check("both-fist pulse ends", !rig.in.bothFistTapPressed());
        rig.pollMs(150);
        check("both-fist hold does not re-fire", !rig.in.bothFistTapPressed());

        rig.lFist = OPEN_FIST;      // release one hand ends the gesture and re-arms
        rig.pollMs(150);
        check("released left fist ends both-fist gesture", !rig.in.bothFistTapPressed());
        rig.lFist = FIST;
        rig.pollMs(150);            // onset
        List<Boolean> second = new ArrayList<>();
        second.add(rig.in.bothFistTapPressed());
        for (int i = 0; i < 3; i++) {
            rig.pollMs(150);
            second.add(rig.in.bothFistTapPressed());
        }
        check("a second both-fist gesture fires a second pulse", countRising(second) == 1);
    }

    // ------------------------------------------------------------------------------------------
    // 6b. both-fist chord priority: the chord owns the fist gesture (F12 integration follow-up)
    // ------------------------------------------------------------------------------------------
    private static void bothFistChordPriority() {
        section("both-fist chord priority (no simultaneous click/Escape/inventory)");
        // (a) a lone single-hand fist tap still works while the other hand is open
        Rig rig = new Rig();
        rig.poll();
        rig.pollMs(150);
        rig.rFist = FIST;
        rig.pollMs(150);            // right hold onset
        List<Boolean> single = new ArrayList<>();
        single.add(rig.in.fistTapPressed(RIGHT));
        for (int i = 0; i < 3; i++) {
            rig.pollMs(150);
            single.add(rig.in.fistTapPressed(RIGHT));
        }
        check("single-hand right fist tap fires (other hand open)", countRising(single) == 1);

        // (b) both fists held -> ONLY the both-fist inventory pulse; per-hand pulses suppressed
        rig.lFist = FIST;
        rig.pollMs(150);            // chord onset
        check("both-fist chord active", rig.in.fistPressed(LEFT) && rig.in.fistPressed(RIGHT));
        List<Boolean> chordLeft = new ArrayList<>();
        List<Boolean> chordRight = new ArrayList<>();
        List<Boolean> chordBoth = new ArrayList<>();
        chordLeft.add(rig.in.fistTapPressed(LEFT));
        chordRight.add(rig.in.fistTapPressed(RIGHT));
        chordBoth.add(rig.in.bothFistTapPressed());
        for (int i = 0; i < 4; i++) {
            rig.pollMs(150);
            chordLeft.add(rig.in.fistTapPressed(LEFT));
            chordRight.add(rig.in.fistTapPressed(RIGHT));
            chordBoth.add(rig.in.bothFistTapPressed());
        }
        check("chord suppresses the per-hand LEFT fist tap", countTrue(chordLeft) == 0);
        check("chord suppresses the per-hand RIGHT fist tap", countTrue(chordRight) == 0);
        check("chord fires exactly one both-fist/inventory pulse", countRising(chordBoth) == 1);
        check("inventory pulse is a 2-frame edge", firstPulseWidth(chordBoth) == 2);

        // (c) chord released while one hand remains held -> no deferred per-hand tap for that hold
        rig.lFist = OPEN_FIST;
        rig.pollMs(150);
        check("chord releases cleanly (no stuck inventory pulse)", !rig.in.bothFistTapPressed());
        List<Boolean> after = new ArrayList<>();
        for (int i = 0; i < 4; i++) {
            rig.pollMs(150);
            after.add(rig.in.fistTapPressed(RIGHT));
        }
        check("remaining held fist does not fire a deferred tap", countTrue(after) == 0);

        // (d) a fresh single-hand hold after the chord fires normally again
        rig.rFist = OPEN_FIST;
        rig.pollMs(150);
        rig.rFist = FIST;
        rig.pollMs(150);            // new right hold onset
        List<Boolean> again = new ArrayList<>();
        again.add(rig.in.fistTapPressed(RIGHT));
        for (int i = 0; i < 3; i++) {
            rig.pollMs(150);
            again.add(rig.in.fistTapPressed(RIGHT));
        }
        check("single-hand tap works again after the chord", countRising(again) == 1);

        // (e) no stuck state once everything releases (let the 2-frame tap pulse drain)
        rig.rFist = OPEN_FIST;
        rig.pollMs(150);
        rig.pollMs(150);
        check("no stuck gesture after the chord", !rig.in.fistPressed(LEFT) && !rig.in.fistPressed(RIGHT)
            && !rig.in.fistTapPressed(LEFT) && !rig.in.fistTapPressed(RIGHT)
            && !rig.in.bothFistTapPressed());

        // (f) chord starts BEFORE either per-hand 400 ms hold: ending it must not release a delayed tap
        Rig early = new Rig();
        early.poll();
        early.pollMs(150);
        early.rFist = FIST;
        early.pollMs(150);          // right hold onset (t=300)
        early.lFist = FIST;
        early.pollMs(150);          // chord starts 150 ms into the right hold (t=450)
        check("early chord active", early.in.fistPressed(LEFT) && early.in.fistPressed(RIGHT));
        early.lFist = OPEN_FIST;
        early.pollMs(150);          // chord ends 300 ms into the right hold (t=600)
        List<Boolean> deferred = new ArrayList<>();
        for (int i = 0; i < 4; i++) { // the right hold crosses its own 400 ms with the chord already over
            early.pollMs(150);
            deferred.add(early.in.fistTapPressed(RIGHT));
        }
        check("chord start consumes the holds (no deferred single-hand tap)", countTrue(deferred) == 0);
        early.rFist = OPEN_FIST;
        early.pollMs(150);
        check("no stuck per-hand pulse after the early chord", !early.in.fistTapPressed(RIGHT)
            && !early.in.fistTapPressed(LEFT) && !early.in.bothFistTapPressed());
    }

    // ------------------------------------------------------------------------------------------
    // 7. per-hand tracking loss releases that hand's sources the same frame
    // ------------------------------------------------------------------------------------------
    private static void trackingLossReleasesSameFrame() {
        section("tracking loss releases that hand on the same frame");
        Rig rig = new Rig();
        rig.poll();
        rig.pollMs(150);
        rig.rPinch = PINCHED;
        rig.pollMs(10);
        check("right pinch pressed before loss", rig.in.pinchPressed(RIGHT));
        rig.rightTracked = false;
        rig.pollMs(10);
        check("right tracking loss releases pinch immediately", !rig.in.pinchPressed(RIGHT));
        check("LEFT hand sources unaffected by right loss", rig.in.isHandTracked(LEFT));
        rig.rightTracked = true;
        rig.rPinch = OPEN_PINCH;
        rig.pollMs(10);
        rig.lPinch = PINCHED;
        rig.pollMs(10);
        check("left pinch pressed", rig.in.pinchPressed(LEFT));
        rig.leftTracked = false;
        rig.pollMs(10);
        check("left tracking loss releases left pinch immediately", !rig.in.pinchPressed(LEFT));
        // both hands lost (valid_mask = 0) -> nothing tracked, nothing pressed
        rig.rightTracked = false;
        rig.pollMs(10);
        check("no hands tracked", !rig.in.isHandTracked(LEFT) && !rig.in.isHandTracked(RIGHT));
        check("no sources pressed", !rig.in.pinchPressed(LEFT) && !rig.in.pinchPressed(RIGHT));
    }

    // ------------------------------------------------------------------------------------------
    // 8. stale input (>250 ms without a new publish) releases everything and recovers
    // ------------------------------------------------------------------------------------------
    private static void staleInputReleasesEverything() {
        section("stale-input release (>250 ms) and recovery");
        VisionInput in = new VisionInput();
        ByteBuffer open0 = snapshot(10, T0, true, true, OPEN_PINCH, OPEN_FIST, OPEN_PINCH, OPEN_FIST);
        in.poll(open0, 0, T0);
        ByteBuffer open150 = snapshot(11, T0 + 150 * MS, true, true, OPEN_PINCH, OPEN_FIST, OPEN_PINCH, OPEN_FIST);
        in.poll(open150, 0, T0 + 150 * MS);
        ByteBuffer pressed = snapshot(12, T0 + 300 * MS, true, true, PINCHED, OPEN_FIST, OPEN_PINCH, OPEN_FIST);
        in.poll(pressed, 0, T0 + 300 * MS);
        check("right pinch pressed before the freeze", in.pinchPressed(RIGHT));
        // compositor freezes: the same snapshot keeps being polled
        in.poll(pressed, 0, T0 + 400 * MS);
        check("100 ms without a new publish is not stale yet", !in.isStale());
        check("held state survives a short freeze", in.pinchPressed(RIGHT));
        in.poll(pressed, 0, T0 + 560 * MS); // 260 ms since the last publish
        check("input is stale after 250 ms", in.isStale());
        check("stale input is not healthy", !in.isInputHealthy());
        check("stale input releases the held pinch", !in.pinchPressed(RIGHT));
        check("stale input marks hands untracked", !in.isHandTracked(RIGHT));
        ByteBuffer resumed = snapshot(13, T0 + 700 * MS, true, true, OPEN_PINCH, OPEN_FIST, OPEN_PINCH, OPEN_FIST);
        in.poll(resumed, 0, T0 + 700 * MS);
        check("a new publish clears the stale state", !in.isStale() && in.isInputHealthy());
        check("hands tracked again after recovery", in.isHandTracked(RIGHT) && in.isHandTracked(LEFT));
    }

    // ------------------------------------------------------------------------------------------
    // 9. malformed input fails safe
    // ------------------------------------------------------------------------------------------
    private static void malformedInputsFailSafe() {
        section("malformed input fails safe (untracked, never a crash)");
        VisionInput in = new VisionInput();
        in.poll(snapshot(0, T0, true, true, OPEN_PINCH, OPEN_FIST, OPEN_PINCH, OPEN_FIST), 0, T0);
        check("healthy before error", in.isInputHealthy());
        boolean accepted = in.poll(null, -5, T0 + 10 * MS);
        check("null snapshot / native error is rejected", !accepted);
        check("native error -> unhealthy", !in.isInputHealthy());
        check("native error -> releases hands", !in.isHandTracked(LEFT) && !in.isHandTracked(RIGHT));

        ByteBuffer shortBuffer = ByteBuffer.allocateDirect(VisionInput.INPUT_BYTES - 4)
            .order(ByteOrder.LITTLE_ENDIAN);
        check("short buffer is rejected", !in.poll(shortBuffer, 0, T0 + 20 * MS));

        VisionInput in2 = new VisionInput();
        ByteBuffer mismatch = snapshot(0, T0, true, true, OPEN_PINCH, OPEN_FIST, OPEN_PINCH, OPEN_FIST);
        mismatch.putInt(VisionInput.INPUT_OFF_HANDS + VisionInput.HAND_RIGHT * VisionInput.HAND_STRIDE
            + VisionInput.HAND_OFF_TRACKED, 0); // valid_mask says right, hand word says not tracked
        in2.poll(mismatch, 0, T0);
        check("valid_mask/hand-bit mismatch flags the hand invalid", in2.invalidHandMask() == 2);
        check("mismatched hand treated as untracked", !in2.isHandTracked(RIGHT));

        ByteBuffer nan = snapshot(0, T0, true, true, OPEN_PINCH, OPEN_FIST, OPEN_PINCH, OPEN_FIST);
        nan.putFloat(VisionInput.INPUT_OFF_HANDS + VisionInput.HAND_LEFT * VisionInput.HAND_STRIDE
            + VisionInput.HAND_OFF_WRIST_POS + 4, Float.NaN);
        VisionInput in3 = new VisionInput();
        in3.poll(nan, 0, T0);
        check("non-finite hand data flags the hand invalid", in3.invalidHandMask() == 1);
        check("non-finite hand treated as untracked", !in3.isHandTracked(LEFT));

        // degenerate palm: fist ratio must not be NaN and must never present a fist
        VisionInput in4 = new VisionInput();
        in4.poll(snapshot(0, T0, true, true, OPEN_PINCH, OPEN_FIST, OPEN_PINCH, OPEN_FIST, 0.0F), 0, T0);
        check("degenerate palm ratio is finite-or-infinite, not NaN", !Float.isNaN(in4.fistRatio(RIGHT)));
        check("degenerate palm never presents a fist", !in4.fistRaw(RIGHT));
    }

    // ------------------------------------------------------------------------------------------
    // 10. action-set gating (MCOpenVR.updateActiveActionSets shape)
    // ------------------------------------------------------------------------------------------
    private static void actionSetGating() {
        section("action-set gating (ingame / gui / contextual / global)");
        Rig rig = new Rig();
        rig.poll();
        rig.pollMs(150);
        rig.rPinch = PINCHED;       // right pinch pressed; left open
        rig.pollMs(10);
        check("right pinch pressed for the gating test", rig.in.pinchPressed(RIGHT));
        VisionInput in = rig.in;

        in.setEnvironment(false, false, false); // no screen
        check("no screen: key.attack active", in.actionActive(VisionInput.KEY_ATTACK));
        check("no screen: key.attack pressed (right pinch)", in.actionPressed(VisionInput.KEY_ATTACK));
        check("no screen: teleport active", in.actionActive(VisionInput.KEY_TELEPORT));
        check("no screen: contextual interact active", in.actionActive(VisionInput.KEY_VR_INTERACT));
        check("no screen: GUI click inactive", !in.actionActive(VisionInput.KEY_GUI_LEFT_CLICK));
        check("no screen: GUI click not pressed", !in.actionPressed(VisionInput.KEY_GUI_LEFT_CLICK));
        check("global action always active", in.actionActive(VisionInput.KEY_INGAME_MENU));
        check("inventory global always active", in.actionActive(VisionInput.KEY_INVENTORY));

        in.setEnvironment(true, false, false);  // inventory screen open
        check("screen open: key.attack inactive", !in.actionActive(VisionInput.KEY_ATTACK));
        check("screen open: attack not pressed", !in.actionPressed(VisionInput.KEY_ATTACK));
        check("screen open: GUI left click active", in.actionActive(VisionInput.KEY_GUI_LEFT_CLICK));
        check("screen open: GUI left click pressed (right pinch)", in.actionPressed(VisionInput.KEY_GUI_LEFT_CLICK));
        check("screen open: teleport inactive", !in.actionActive(VisionInput.KEY_TELEPORT));
        check("screen open: contextual inactive", !in.actionActive(VisionInput.KEY_VR_INTERACT));
        check("screen open: menu stays global", in.actionActive(VisionInput.KEY_INGAME_MENU));

        in.setEnvironment(true, true, false);   // ingameBindingsInGui
        check("ingame bindings in GUI: attack active", in.actionActive(VisionInput.KEY_ATTACK));
        check("ingame bindings in GUI: teleport active", in.actionActive(VisionInput.KEY_TELEPORT));
        check("ingame bindings in GUI: contextual still inactive", !in.actionActive(VisionInput.KEY_VR_INTERACT));

        in.setEnvironment(false, false, true);  // keyboard/radial overlay
        check("keyboard overlay: ingame still active", in.actionActive(VisionInput.KEY_ATTACK));
        check("keyboard overlay: GUI inactive", !in.actionActive(VisionInput.KEY_GUI_LEFT_CLICK));
    }

    // ------------------------------------------------------------------------------------------
    // 11. binding table coverage (design §5.4, exact KeyMapping names, origins 1=L / 2=R)
    // ------------------------------------------------------------------------------------------
    private static void bindingTableCoverage() {
        section("binding table coverage + origins (design §5.4)");
        VisionInput in = new VisionInput();
        List<String> actual = new ArrayList<>();
        for (int i = 0; i < in.bindingCount(); i++) {
            actual.add(in.bindingAction(i) + "|" + in.bindingHand(i) + "|"
                + in.bindingActionSet(i) + "|" + in.bindingOrigin(i));
        }
        Collections.sort(actual);
        List<String> expected = new ArrayList<>(List.of(
            "key.attack|1|INGAME|2",
            "key.use|1|INGAME|2",
            "key.inventory|-1|GLOBAL|2",
            "vivecraft.key.teleport|0|INGAME|1",
            "vivecraft.key.vrInteract|0|CONTEXTUAL|1",
            "vivecraft.key.vrInteract|1|CONTEXTUAL|2",
            "vivecraft.key.climbeyGrab|0|CONTEXTUAL|1",
            "vivecraft.key.climbeyGrab|1|CONTEXTUAL|2",
            "vivecraft.key.guiLeftClick|1|GUI|2",
            "vivecraft.key.guiRightClick|1|GUI|2",
            "vivecraft.key.guiShift|0|GUI|1",
            "vivecraft.key.ingameMenuButton|0|GLOBAL|1",
            "key.jump|1|INGAME|2",
            "key.sneak|1|INGAME|2",
            "vivecraft.key.radialMenu|1|INGAME|2",
            "vivecraft.key.hotbarNext|1|INGAME|2",
            "vivecraft.key.hotbarPrev|1|INGAME|2",
            "vivecraft.key.toggleKeyboard|0|GLOBAL|1",
            "key.chat|0|GLOBAL|1",
            "key.swapOffhand|0|INGAME|1",
            "key.drop|0|INGAME|1",
            "vivecraft.key.climbeyJump|-1|CONTEXTUAL|2"));
        Collections.sort(expected);
        check("exactly 22 binding rows (W1 + W3/W4 middle/swipe + climb-jump chord)", in.bindingCount() == expected.size());
        check("binding table matches design §5.4 exactly", actual.equals(expected));
        if (!actual.equals(expected)) {
            System.out.println("  actual  =" + actual);
            System.out.println("  expected=" + expected);
        }
        check("20 unique bound actions", VisionInput.ACTION_NAMES.length == 20);
        checkEquals("key.attack origins", VisionInput.origins(VisionInput.KEY_ATTACK), 2L);
        checkEquals("teleport origins", VisionInput.origins(VisionInput.KEY_TELEPORT), 1L);
        checkEquals("guiShift origins", VisionInput.origins(VisionInput.KEY_GUI_SHIFT), 1L);
        checkEquals("menu origins", VisionInput.origins(VisionInput.KEY_INGAME_MENU), 1L);
        checkList("vrInteract origins L+R", VisionInput.origins(VisionInput.KEY_VR_INTERACT), 1L, 2L);
        checkList("climbeyGrab origins L+R", VisionInput.origins(VisionInput.KEY_CLIMBEY_GRAB), 1L, 2L);
        checkList("inventory origins (both fists)", VisionInput.origins(VisionInput.KEY_INVENTORY), 1L, 2L);
        checkList("unbound action has no origins", VisionInput.origins("key.command"), new Long[0]);
        check("all 20 design names are bound (W1 + W3/W4)",
            in.isBound(VisionInput.KEY_ATTACK) && in.isBound(VisionInput.KEY_USE)
                && in.isBound(VisionInput.KEY_INVENTORY) && in.isBound(VisionInput.KEY_TELEPORT)
                && in.isBound(VisionInput.KEY_VR_INTERACT) && in.isBound(VisionInput.KEY_CLIMBEY_GRAB)
                && in.isBound(VisionInput.KEY_GUI_LEFT_CLICK) && in.isBound(VisionInput.KEY_GUI_RIGHT_CLICK)
                && in.isBound(VisionInput.KEY_GUI_SHIFT) && in.isBound(VisionInput.KEY_INGAME_MENU)
                && in.isBound(VisionInput.KEY_JUMP) && in.isBound(VisionInput.KEY_SNEAK)
                && in.isBound(VisionInput.KEY_RADIAL_MENU)
                && in.isBound(VisionInput.KEY_HOTBAR_NEXT) && in.isBound(VisionInput.KEY_HOTBAR_PREV)
                && in.isBound(VisionInput.KEY_TOGGLE_KEYBOARD) && in.isBound(VisionInput.KEY_CHAT)
                && in.isBound(VisionInput.KEY_SWAP_OFFHAND) && in.isBound(VisionInput.KEY_DROP)
                && in.isBound(VisionInput.KEY_CLIMBEY_JUMP));
    }

    // ------------------------------------------------------------------------------------------
    // 12. tuning overrides (file Map + -D system properties, read once)
    // ------------------------------------------------------------------------------------------
    private static void tuningSummary() {
        section("tuning summary for status diagnostics");
        VisionInput in = new VisionInput(Map.of(
            VisionInput.TUNE_MIDDLE_ON, "0.04",
            VisionInput.TUNE_SWIPE_ENABLED, "true"));
        String summary = in.tuningSummary();
        check("summary contains pinch thresholds", summary.contains("pinch=0.030/0.045"));
        check("summary contains middle override", summary.contains("middle=true 0.040/0.050"));
        check("summary contains swipe enabled", summary.contains("swipe=true"));
        check("summary contains arm/stale", summary.contains("armMs=100") && summary.contains("staleMs=250"));
    }

    private static void tuningOverrides() {
        section("tuning overrides (Map + system properties)");
        VisionInput defaults = new VisionInput();
        checkClose("default pinchOn", defaults.pinchOn(), VisionInput.DEFAULT_PINCH_ON, 0.0F);
        checkClose("default pinchOff", defaults.pinchOff(), VisionInput.DEFAULT_PINCH_OFF, 0.0F);
        checkClose("default fistOn", defaults.fistOn(), VisionInput.DEFAULT_FIST_ON, 0.0F);
        checkClose("default fistOff", defaults.fistOff(), VisionInput.DEFAULT_FIST_OFF, 0.0F);
        check("default holdMs", defaults.fistHoldMillis() == VisionInput.DEFAULT_FIST_HOLD_MS);
        check("default armMs", defaults.armMillis() == VisionInput.DEFAULT_ARM_MS);
        check("default staleMs", defaults.staleMillis() == VisionInput.DEFAULT_STALE_MS);
        check("default tapFrames", defaults.tapFrames() == VisionInput.DEFAULT_TAP_FRAMES);

        VisionInput fileTuned = new VisionInput(Map.of(
            VisionInput.TUNE_PINCH_ON, "0.02",
            VisionInput.TUNE_PINCH_OFF, "0.03",
            VisionInput.TUNE_FIST_ON, "1.00",
            VisionInput.TUNE_FIST_OFF, "1.20",
            VisionInput.TUNE_FIST_HOLD_MS, "300",
            VisionInput.TUNE_ARM_MS, "50",
            VisionInput.TUNE_STALE_MS, "200",
            VisionInput.TUNE_TAP_FRAMES, "3"));
        checkClose("Map pinchOn override", fileTuned.pinchOn(), 0.02F, 0.0F);
        checkClose("Map pinchOff override", fileTuned.pinchOff(), 0.03F, 0.0F);
        checkClose("Map fistOn override", fileTuned.fistOn(), 1.00F, 0.0F);
        checkClose("Map fistOff override", fileTuned.fistOff(), 1.20F, 0.0F);
        check("Map holdMs override", fileTuned.fistHoldMillis() == 300L);
        check("Map armMs override", fileTuned.armMillis() == 50L);
        check("Map staleMs override", fileTuned.staleMillis() == 200L);
        check("Map tapFrames override", fileTuned.tapFrames() == 3);

        VisionInput invalid = new VisionInput(Map.of(
            VisionInput.TUNE_PINCH_ON, "not-a-number",
            VisionInput.TUNE_ARM_MS, "-5"));
        checkClose("invalid tuning falls back to default", invalid.pinchOn(), VisionInput.DEFAULT_PINCH_ON, 0.0F);
        check("negative tuning falls back to default", invalid.armMillis() == VisionInput.DEFAULT_ARM_MS);

        System.setProperty(VisionInput.TUNE_PROPERTY_PREFIX + VisionInput.TUNE_ARM_MS, "50");
        try {
            VisionInput propTuned = new VisionInput(Map.of(VisionInput.TUNE_ARM_MS, "500"));
            check("system property overrides the file Map", propTuned.armMillis() == 50L);
        } finally {
            System.clearProperty(VisionInput.TUNE_PROPERTY_PREFIX + VisionInput.TUNE_ARM_MS);
        }

        // behavioural proof: a tuned pinchOn (0.06) presses at 0.055 where the default would not
        VisionInput tuned = new VisionInput(Map.of(VisionInput.TUNE_PINCH_ON, "0.06", VisionInput.TUNE_PINCH_OFF, "0.07"));
        Rig tunedRig = new Rig(tuned);
        tunedRig.poll();
        tunedRig.pollMs(150);
        tunedRig.rPinch = 0.055F;
        tunedRig.pollMs(10);
        check("tuned pinchOn presses at 0.055", tunedRig.in.pinchPressed(RIGHT));
        Rig defaultRig = new Rig();
        defaultRig.poll();
        defaultRig.pollMs(150);
        defaultRig.rPinch = 0.055F;
        defaultRig.pollMs(10);
        check("default engine does not press at 0.055", !defaultRig.in.pinchPressed(RIGHT));
    }

    // ------------------------------------------------------------------------------------------
    // Infrastructure: synthetic 752-byte snapshots + test clock
    // ------------------------------------------------------------------------------------------

    private static ByteBuffer snapshot(int frameIndex, long timestampNs, boolean leftTracked, boolean rightTracked,
                                      float rightPinch, float rightFist, float leftPinch, float leftFist) {
        return snapshot(frameIndex, timestampNs, leftTracked, rightTracked, rightPinch, rightFist, leftPinch,
            leftFist, PALM);
    }

    /** Build one synthetic vrmc_input_state: hands[] = LEFT THEN RIGHT, joints at documented offsets. */
    private static ByteBuffer snapshot(int frameIndex, long timestampNs, boolean leftTracked, boolean rightTracked,
                                      float rightPinch, float rightFist, float leftPinch, float leftFist,
                                      float palm) {
        ByteBuffer b = ByteBuffer.allocateDirect(VisionInput.INPUT_BYTES).order(ByteOrder.LITTLE_ENDIAN);
        b.putInt(VisionInput.INPUT_OFF_FRAME_INDEX, frameIndex);
        b.putInt(VisionInput.INPUT_OFF_VALID_MASK, (leftTracked ? 1 : 0) | (rightTracked ? 2 : 0));
        b.putLong(VisionInput.INPUT_OFF_TIMESTAMP, timestampNs);
        writeHand(b, VisionInput.INPUT_OFF_HANDS + VisionInput.HAND_LEFT * VisionInput.HAND_STRIDE,
            false, leftTracked, leftPinch, leftFist, palm);
        writeHand(b, VisionInput.INPUT_OFF_HANDS + VisionInput.HAND_RIGHT * VisionInput.HAND_STRIDE,
            true, rightTracked, rightPinch, rightFist, palm);
        b.position(0);
        return b;
    }

    private static void writeHand(ByteBuffer b, int base, boolean right, boolean tracked,
                                  float pinchDistance, float fistRatio, float palm) {
        b.putInt(base + VisionInput.HAND_OFF_TRACKED, tracked ? 1 : 0);
        b.putInt(base + VisionInput.HAND_OFF_CHIRALITY, right ? 1 : 0);
        b.putLong(base + VisionInput.HAND_OFF_TIMESTAMP, 0L);
        b.putFloat(base + VisionInput.HAND_OFF_WRIST_QUAT, 0.0F);
        b.putFloat(base + VisionInput.HAND_OFF_WRIST_QUAT + 4, 0.0F);
        b.putFloat(base + VisionInput.HAND_OFF_WRIST_QUAT + 8, 0.0F);
        b.putFloat(base + VisionInput.HAND_OFF_WRIST_QUAT + 12, 1.0F);
        float wristX = right ? 0.18F : -0.18F;
        float wristY = 1.2F;
        float wristZ = -0.4F;
        b.putFloat(base + VisionInput.HAND_OFF_WRIST_POS, wristX);
        b.putFloat(base + VisionInput.HAND_OFF_WRIST_POS + 4, wristY);
        b.putFloat(base + VisionInput.HAND_OFF_WRIST_POS + 8, wristZ);
        float[] j = new float[VisionInput.JOINT_COUNT * 3];
        for (int i = 0; i < VisionInput.JOINT_COUNT; i++) {
            j[i * 3] = wristX;
            j[i * 3 + 1] = wristY;
            j[i * 3 + 2] = wristZ;
        }
        // middle knuckle at one palm length in front of the wrist
        setJoint(j, VisionInput.JOINT_MIDDLE_KNUCKLE, wristX, wristY, wristZ - palm);
        // curled/open finger tips at fistRatio * palm from the wrist
        float tipZ = wristZ - fistRatio * palm;
        for (int tip : FINGER_TIPS) {
            setJoint(j, tip, wristX, wristY, tipZ);
        }
        // thumb tip exactly pinchDistance from the index tip
        setJoint(j, VisionInput.JOINT_THUMB_TIP, wristX + pinchDistance, wristY, tipZ);
        // index/little metacarpals give the palm side axis (perpendicular to the aim)
        setJoint(j, VisionInput.JOINT_INDEX_METACARPAL, wristX + 0.03F, wristY, wristZ - 0.02F);
        setJoint(j, VisionInput.JOINT_LITTLE_METACARPAL, wristX - 0.03F, wristY, wristZ - 0.02F);
        for (int i = 0; i < j.length; i++) {
            b.putFloat(base + VisionInput.HAND_OFF_JOINTS + i * 4, j[i]);
        }
    }

    private static void setJoint(float[] joints, int joint, float x, float y, float z) {
        joints[joint * 3] = x;
        joints[joint * 3 + 1] = y;
        joints[joint * 3 + 2] = z;
    }

    private static final class Rig {
        final VisionInput in;
        int frame;
        long now = T0;
        boolean leftTracked = true;
        boolean rightTracked = true;
        float lPinch = OPEN_PINCH;
        float rPinch = OPEN_PINCH;
        float lFist = OPEN_FIST;
        float rFist = OPEN_FIST;

        Rig() { this(new VisionInput()); }
        Rig(VisionInput in) { this.in = in; }

        void poll() { pollMs(0); }

        void pollMs(long millis) {
            now += millis * MS;
            in.poll(snapshot(frame++, now, leftTracked, rightTracked, rPinch, rFist, lPinch, lFist), 0, now);
        }
    }

    /** Width (in frames) of the first true run in the trace; 0 if there is none. */
    private static int firstPulseWidth(List<Boolean> values) {
        int i = 0;
        while (i < values.size() && !values.get(i)) i++;
        int width = 0;
        while (i < values.size() && values.get(i)) {
            width++;
            i++;
        }
        return width;
    }

    private static boolean anyTrue(List<Boolean> values, int from, int toExclusive) {
        for (int i = from; i < toExclusive; i++) {
            if (values.get(i)) return true;
        }
        return false;
    }

    private static int countRising(List<Boolean> values) {
        int rising = 0;
        boolean prev = false;
        for (boolean v : values) {
            if (v && !prev) rising++;
            prev = v;
        }
        return rising;
    }

    private static int countTrue(List<Boolean> values) {
        int n = 0;
        for (boolean v : values) if (v) n++;
        return n;
    }

    // ------------------------------------------------------------------------------------------
    // Assertions
    // ------------------------------------------------------------------------------------------

    private static void section(String name) {
        System.out.println();
        System.out.println("== " + name + " ==");
    }

    private static void check(String label, boolean ok) {
        checks++;
        if (!ok) failures++;
        System.out.printf("  %-78s %s%n", label, ok ? "ok" : "FAIL");
    }

    private static void checkClose(String label, float actual, float expected, float epsilon) {
        boolean ok = Float.isFinite(actual) && Math.abs(actual - expected) <= epsilon;
        check(label + " (actual=" + actual + " expected=" + expected + ")", ok);
    }

    private static void checkEquals(String label, List<Long> actual, Long expected) {
        check(label + " == [" + expected + "] (actual=" + actual + ")",
            actual.size() == 1 && actual.get(0).equals(expected));
    }

    private static void checkList(String label, List<Long> actual, Long... expected) {
        check(label + " == " + List.of(expected) + " (actual=" + actual + ")",
            actual.equals(List.of(expected)));
    }
}
