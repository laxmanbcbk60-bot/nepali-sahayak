package com.maya.ai

import com.maya.ai.actions.ActionParser
import com.maya.ai.actions.MayaAction
import com.maya.ai.actions.SettingsSection
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ActionParserTest {
    @Test fun parsesYouTubeSearchAndStripsTag() {
        val r = ActionParser.parse("हुन्छ, खोज्दैछु।\n<maya_action>{\"type\":\"youtube_search\",\"query\":\"नेपाली गीत\"}</maya_action>")
        assertEquals(listOf<MayaAction>(MayaAction.YouTubeSearch("नेपाली गीत")), r.actions)
        assertEquals("हुन्छ, खोज्दैछु।", r.displayText)
        assertTrue(r.rejected.isEmpty())
    }

    @Test fun rejectsUnknownActionType() {
        val r = ActionParser.parse("<maya_action>{\"type\":\"shell\",\"cmd\":\"rm -rf /\"}</maya_action>")
        assertTrue(r.actions.isEmpty())
        assertEquals(1, r.rejected.size)
    }

    @Test fun rejectsMalformedJson() {
        val r = ActionParser.parse("hi <maya_action>{oops</maya_action>")
        assertTrue(r.actions.isEmpty())
        assertEquals("hi", r.displayText)
    }

    @Test fun urlMustBeHttps() {
        assertNull(ActionParser.validateUrl("http://example.com"))
        assertNull(ActionParser.validateUrl("javascript:alert(1)"))
        assertNull(ActionParser.validateUrl("intent://x#Intent;end"))
        assertNull(ActionParser.validateUrl("https://user:pw@example.com"))
        assertEquals("https://example.com/a", ActionParser.validateUrl("https://example.com/a"))
    }

    @Test fun youtubeUrlDetection() {
        assertTrue(ActionParser.isYouTubeUrl("https://youtu.be/abc123"))
        assertTrue(ActionParser.isYouTubeUrl("https://music.youtube.com/watch?v=x"))
        assertFalse(ActionParser.isYouTubeUrl("https://youtube.com.evil.io/watch"))
    }

    @Test fun dialValidationAndConfirmation() {
        val ok = ActionParser.parse("<maya_action>{\"type\":\"dial\",\"number\":\"+977 9800000000\"}</maya_action>")
        assertEquals(1, ok.actions.size)
        assertTrue(ok.actions[0].requiresConfirmation)
        val bad = ActionParser.parse("<maya_action>{\"type\":\"dial\",\"number\":\"*21*123#\"}</maya_action>")
        assertTrue(bad.actions.isEmpty())
    }

    @Test fun settingsSectionAllowlist() {
        val ok = ActionParser.parse("<maya_action>{\"type\":\"open_settings\",\"section\":\"wifi\"}</maya_action>")
        assertEquals(MayaAction.OpenSettings(SettingsSection.WIFI), ok.actions[0])
        val bad = ActionParser.parse("<maya_action>{\"type\":\"open_settings\",\"section\":\"accessibility\"}</maya_action>")
        assertTrue(bad.actions.isEmpty())
    }

    @Test fun limitsActionsPerReply() {
        val one = "<maya_action>{\"type\":\"open_app\",\"app\":\"Calculator\"}</maya_action>"
        val r = ActionParser.parse(one.repeat(5))
        assertEquals(ActionParser.MAX_ACTIONS, r.actions.size)
        assertEquals(1, r.rejected.size)
    }

    @Test fun plainReplyHasNoActions() {
        val r = ActionParser.parse("Just chatting 😊")
        assertTrue(r.actions.isEmpty())
        assertEquals("Just chatting 😊", r.displayText)
    }
}
