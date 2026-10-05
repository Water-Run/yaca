#!/usr/bin/env python3
# Author: WaterRun
# Date: 2026-10-05
# File: terminal_approval_test.py
# Description: Ensure online terminal probes approve only the explicit print-only Lua operation.

import importlib.util
import json
import pathlib
import unittest

ROOT=pathlib.Path(__file__).resolve().parents[2]
SPEC=importlib.util.spec_from_file_location('agent_terminal_smoke',ROOT/'.tools/qualification/agent_terminal_smoke.py')
TERMINAL=importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(TERMINAL)


#@class ApprovalTest Verifies captured approval cards without sending terminal input or running tools.
class ApprovalTest(unittest.TestCase):
    # Construct a small transcript card with explicit tool and canonical argument fields.
    #@param self ApprovalTest Test instance with no mutable external state.
    #@param tool str Claimed built-in tool name.
    #@param arguments str Canonical JSON argument line under test.
    #@return bytes Complete deny-default approval card.
    def card(self,tool,arguments):
        return ('[ACTION approval-1]\ntool: '+tool+'\narguments: '+arguments+
                '\nallow approval-1 once | deny approval-1 | details approval-1\ndefault: deny\n?? ').encode()

    # Accept exactly the authorized Lua probe, including native canonical defaults and ANSI headers.
    #@param self ApprovalTest Test instance.
    #@return None Assertions fail if valid print-only proposals are rejected.
    def test_print_only_lua_card_is_accepted(self):
        card=self.card('lua','{"args":[],"code":"print(6*7)","cwd":"C:\\\\probe","deadline_ms":1000}')
        TERMINAL.verify_lua_approval(b'\x1b[32m'+card+b'\x1b[0m')

    # Refuse unexpected tools, extra Lua source and arguments before the harness can approve them.
    #@param self ApprovalTest Test instance.
    #@return None Assertions require every changed operation to raise.
    def test_other_effects_are_refused(self):
        for tool,arguments in (('exec','{"command":"echo 42"}'),
                               ('lua',json.dumps({'code':'print(6*7); os.execute("echo changed")'})),
                               ('lua','{"code":"print(6*7)","args":["extra"]}')):
            with self.subTest(tool=tool,arguments=arguments):
                with self.assertRaises(AssertionError):
                    TERMINAL.verify_lua_approval(self.card(tool,arguments))

    # Reject model text escaped to resemble a card and an incomplete trusted card.
    #@param self ApprovalTest Test instance.
    #@return None Assertions require an actual complete program card.
    def test_forged_or_incomplete_cards_do_not_authorize(self):
        card=self.card('lua','{"code":"print(6*7)"}')
        with self.assertRaises(AssertionError):
            TERMINAL.verify_lua_approval(b'\\'+card)
        with self.assertRaises(AssertionError):
            TERMINAL.verify_lua_approval(card.replace(b'default: deny\n',b''))

    # Accept a declined second request without treating it as a second execution or identity change.
    #@param self ApprovalTest Test instance with no external state.
    #@return None Assertions bind the proposal, progress and completion to the executed call only.
    def test_declined_request_is_not_another_execution(self):
        transcript=(b'[TOOL tool-1]\nname: lua\narguments: {"code":"print(6*7)"}\n'
                    b'[TOOL tool-1]\nstdout: withheld-until-terminal-secret-scan\n'
                    b'[TOOL tool-1]\nprocess outcome: completed\n'
                    b'[TOOL tool-2]\nname: lua\narguments: {"code":"print(6*7)"}\n'
                    b'[STATUS]\nAction review completed.\n')
        self.assertEqual(TERMINAL.verify_lua_execution(transcript),'tool-1')

    # Refuse a second process completion and progress or terminal events with a different display identity.
    #@param self ApprovalTest Test instance.
    #@return None Assertions require false execution counts and ID drift to fail.
    def test_extra_execution_and_identity_drift_are_refused(self):
        proposal=b'[TOOL tool-1]\nname: lua\narguments: {"code":"print(6*7)"}\n'
        terminal=b'[TOOL tool-1]\nprocess outcome: completed\n'
        for transcript in (proposal+terminal+terminal,
                           proposal+b'[TOOL tool-2]\nprocess outcome: completed\n',
                           proposal+b'[TOOL tool-2]\nstdout: progress\n'+terminal,
                           proposal+terminal+b'[TOOL tool-2]\nname: exec\n'):
            with self.subTest(transcript=transcript):
                with self.assertRaises(AssertionError):
                    TERMINAL.verify_lua_execution(transcript)

    # Accept a continued Ask sequence instead of assuming its counter resets after reopening.
    #@param self ApprovalTest Test instance.
    #@return None Assertions require the exact random token in the completed accepted Ask.
    def test_restored_ask_counter_continues(self):
        transcript=(b'[STATUS]\nAsk request accepted: ask-37\n>>\n'
                    b'[ASK ask-37]\nyaca-memory-1234\n'
                    b'[STATUS]\nAsk ask-37 outcome: completed\n')
        self.assertEqual(TERMINAL.verify_recalled_token(transcript,'yaca-memory-1234'),'ask-37')

    # Refuse guessed answers, split Ask identity, unfinished output and hidden tool activity.
    #@param self ApprovalTest Test instance.
    #@return None Assertions verify a restored session cannot pass without the exact committed token.
    def test_false_recall_evidence_is_refused(self):
        transcript=(b'Ask request accepted: ask-4\n[ASK ask-4]\nyaca-memory-1234\n'
                    b'[STATUS]\nAsk ask-4 outcome: completed\n')
        for value in (transcript.replace(b'yaca-memory-1234',b'42'),
                      transcript.replace(b'[ASK ask-4]',b'[ASK ask-1]'),
                      transcript.replace(b'outcome: completed',b'outcome: failed'),
                      transcript+b'[TOOL tool-1]\nname: lua\n'):
            with self.subTest(transcript=value):
                with self.assertRaises(AssertionError):
                    TERMINAL.verify_recalled_token(value,'yaca-memory-1234')


if __name__=='__main__':
    unittest.main()
