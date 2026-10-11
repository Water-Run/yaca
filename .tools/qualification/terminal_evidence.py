# Author: WaterRun
# Date: 2026-10-11
# File: terminal_evidence.py
# Description: Validates real terminal approval, Lua execution and durable recall evidence independently of the transport or Python 2/3 host.

import json
import re


# Verify the latest genuine approval card binds only the authorized print-only Lua probe.
#@param transcript bytes Captured turn output; escaped model/user chrome is not an approval card.
#@return None No value; every other tool, code body, argument list or incomplete card raises AssertionError.
#@error Refuses approval before input is sent when the proposed operation differs from the probe.
def verify_lua_approval(transcript):
    plain=re.sub(br'\x1b\[[0-?]*[ -/]*[@-~]',b'',transcript).replace(b'\r',b'')
    cards=list(re.finditer(br'(?:^|\n)\[ACTION approval-1\]\n',plain))
    assert cards, 'the expected approval card was not displayed'
    card=plain[cards[-1].end():]
    assert re.search(br'^tool: lua$',card,re.M), 'the pending tool is not the Lua probe'
    assert b'allow approval-1 once | deny approval-1 | details approval-1' in card
    assert re.search(br'^default: deny$',card,re.M), 'approval card is incomplete'
    line=re.search(br'^arguments: ([^\n]+)$',card,re.M)
    assert line, 'approval arguments are unavailable'
    try:
        arguments=json.loads(line.group(1).decode('utf-8'))
    except (ValueError,UnicodeError):
        raise AssertionError('approval arguments are not complete UTF-8 JSON')
    assert isinstance(arguments,dict) and set(arguments)<= {'code','args','cwd','deadline_ms'}
    assert arguments.get('code')=='print(6*7)', 'Lua probe code changed'
    assert arguments.get('args',[])==[], 'Lua probe acquired extra arguments'
    if 'deadline_ms' in arguments:
        assert type(arguments['deadline_ms']) is int and arguments['deadline_ms']>0


# Verify one admitted Lua execution while allowing separately identified requests that never ran.
#@param transcript bytes Trusted turn transcript collected after the explicit approval.
#@return str Display ID whose requested arguments, progress and completed outcome agree.
#@error Raises on changed code/tools, a second execution, missing proposal or split execution identity.
def verify_lua_execution(transcript):
    plain=re.sub(br'\x1b\[[0-?]*[ -/]*[@-~]',b'',transcript).replace(b'\r',b'')
    headers=list(re.finditer(br'(?:^|\n)\[TOOL (tool-[0-9]+)\]\n',plain))
    proposals={}
    progress=set()
    completed=[]
    for index,header in enumerate(headers):
        identity=header.group(1)
        end=headers[index+1].start() if index+1<len(headers) else len(plain)
        block=plain[header.end():end]
        block=re.split(br'\n(?=\[|>>|\?\?)',block,maxsplit=1)[0]
        name=re.search(br'^name: ([^\n]+)$',block,re.M)
        if name:
            assert name.group(1)==b'lua', 'the turn requested a different tool'
        arguments=re.search(br'^arguments: ([^\n]+)$',block,re.M)
        if arguments:
            value=json.loads(arguments.group(1).decode('utf-8'))
            assert isinstance(value,dict) and set(value)<= {'code','args','cwd','deadline_ms'}
            assert value.get('code')=='print(6*7)' and value.get('args',[])==[], \
                'a Lua request differs from the print-only probe'
            assert identity not in proposals or proposals[identity]==value, 'tool proposal changed identity'
            proposals[identity]=value
        if re.search(br'^(stdout|stderr): ',block,re.M):
            progress.add(identity)
        outcome=re.search(br'^process outcome: ([^\n]+)$',block,re.M)
        if outcome:
            assert outcome.group(1)==b'completed', 'Lua execution did not complete'
            completed.append(identity)
    assert len(completed)==1, 'the turn did not complete exactly one Lua execution'
    identity=completed[0]
    assert identity in proposals, 'execution identity differs from its proposal'
    assert progress<= {identity}, 'execution progress acquired a different display ID'
    return identity.decode('ascii')


# Verify the restored Ask uses its durable sequence and recalls only the hidden expected token.
#@param transcript bytes One restored Ask transcript; the submitted question contains no answer token.
#@param token str Random token committed by a main turn in the earlier process.
#@return str Accepted Ask ID whose answer starts with the exact nonce, optionally in bold/inline code; citations may repeat that same value.
#@error Raises for conflicting identities, any different nonce, an incomplete response, a prefixed answer or tool activity.
def verify_recalled_token(transcript,token):
    plain=re.sub(br'\x1b\[[0-?]*[ -/]*[@-~]',b'',transcript).replace(b'\r',b'')
    identities=re.findall(br'^Ask request accepted: (ask-[0-9]+)$',plain,re.M)
    assert len(identities)==1, 'restored Ask identity is missing or ambiguous'
    identity=identities[0]
    answer=re.search(br'(?:^|\n)\[ASK '+identity+br'\]\n(.*?)\n\[STATUS\]\nAsk '
                     +identity+br' outcome: completed(?:\n|$)',plain,re.S)
    body=answer.group(1).strip() if answer else b''
    expected=token.encode('utf-8')
    occurrences=re.findall(br'yaca-memory-[A-Za-z0-9_-]+',body)
    accepted_lines=(expected, b'**'+expected+b'**', b'`'+expected+b'`')
    assert body.splitlines() and body.splitlines()[0] in accepted_lines and set(occurrences)=={expected}, \
        "reopened Context did not recall the earlier main turn's verification token"
    assert not re.search(br'^\[TOOL ',plain,re.M), 'restored pure Ask invoked a tool'
    return identity.decode('ascii')


