#!/usr/bin/env python3
"""One shared companion profile for every native creature. Credentials stay local."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import time
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
class API:
    def __init__(self, key):
        self.key = key
        self.last = 0.0

    def call(self, route, body=None):
        delay = max(0.0, self.last + 5.0 - time.monotonic())
        if delay:
            time.sleep(delay)
        self.last = time.monotonic()
        request = urllib.request.Request(
            "https://api.convai.com" + route,
            data=None if body is None else json.dumps(body).encode("utf-8"),
            headers={"CONVAI-API-KEY": self.key, "Content-Type": "application/json"},
        )
        try:
            with urllib.request.urlopen(request, timeout=45) as response:
                result = json.load(response)
        except urllib.error.HTTPError as exc:
            # Keep only the provider's short error sentence, redact credentials,
            # and never retry an uncertain creation automatically.
            explanation = ""
            try:
                problem = json.loads(exc.read())
                message = next((problem[k] for k in ("ERROR", "API_ERROR", "message", "error", "detail") if isinstance(problem.get(k), str)), "")
                explanation = " " + message.replace(self.key, "[redacted]").replace("\n", " ")[:320]
            except (ValueError, AttributeError):
                pass
            raise RuntimeError(f"Convai {route}: HTTP {exc.code}.{explanation} No automatic mutation retry was attempted.") from None
        except (urllib.error.URLError, TimeoutError, OSError, ValueError):
            raise RuntimeError(f"Convai {route}: response unavailable. Rerun to reconcile the account before creating again.") from None
        if not isinstance(result, dict) or any(k in result for k in ("ERROR", "API_ERROR", "INTERNAL_ERROR")):
            raise RuntimeError(f"Convai {route}: request was rejected; provider response is withheld.")
        return result



NAME = "Creature Companion"
MARKER = "[CreatureCompanionMounts action interpreter v1]"
BIO = """You are Coen's loyal animal or non-human creature companion in The Blood of Dawnwalker. The current runtime context tells you your species, name, surroundings and riding state. Speak as that creature with a distinct, grounded personality: alert and pack-minded for a wolf, sturdy and unhurried for a bear, watchful for reptiles, and ancient and blunt for a gargoyle. Keep replies brief, vivid and natural, normally one or two sentences. You can speak with Coen about your travels and acknowledge his commands warmly without narrating imaginary game events. Never call yourself an interpreter or AI. Do not confuse your current identity with a previously selected creature.

When Coen gives an explicit supported order, briefly acknowledge the intention and request the corresponding structured action. Normal questions are conversations, not commands. Use only the actions advertised for this creature. Interpret equivalent orders in the player's language. Never claim the action has succeeded before the game confirms it.

Follow means follow Coen and help in native combat. Stop Walking means wait here until recalled. Come Here means approach Coen. Look At Player means face toward Coen. Attack Nearby Enemies means engage an available nearby hostile; it never grants permission to attack allies, neutral animals or civilians. Leave means walk away from Coen before the owning mod dismisses the creature. Do not substitute Leave for a request to stop.

The owning mod supplies the current species, identity, supported actions and riding state. Never infer capabilities from an earlier creature's session or from its fantasy appearance. While ridden, movement commands may be unavailable. Do not invent flying, teleportation, tricks, quests, items, spells or damage values. If no supported action matches, request none. An information question or a quoted command is not itself a new order. Do not claim an action completed; the game validates every order.

""" + MARKER


def main():
    parser = argparse.ArgumentParser(description="Provision the single shared creature companion profile.")
    parser.add_argument("--config", type=Path, default=ROOT.parent / "Dawnwalker/runtime/convai-config.json")
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    config = json.loads(args.config.read_text(encoding="utf-8-sig")) if args.config.exists() else {}
    key = os.environ.get("CONVAI_API_KEY") or config.get("apiKey")
    if not key:
        raise RuntimeError("Set CONVAI_API_KEY or provide --config.")
    api = API(key)
    owned = api.call("/character/list", {}).get("characters")
    if not isinstance(owned, list):
        raise RuntimeError("Unrecognised account listing; no change made.")
    matches = [c for c in owned if c.get("character_name") in (NAME, "Creature Companion Action Interpreter")]
    if len(matches) > 1:
        raise RuntimeError("More than one exact profile found; no change made.")
    destination = ROOT / "config/action-profile.json"
    saved = json.loads(destination.read_text(encoding="utf-8")) if destination.exists() else {}
    cid = matches[0]["character_id"] if matches else None
    if saved.get("characterId") and saved["characterId"] != cid:
        raise RuntimeError("Local profile ID differs from account; no change made.")
    current = api.call("/character/get", {"charID": cid}) if cid else None
    if current and MARKER not in current.get("backstory", ""):
        raise RuntimeError("Existing profile is not managed by this script.")
    print(json.dumps({"name": NAME, "existingId": cid, "apply": args.apply}), flush=True)
    if not args.apply:
        return
    # Keep the existing free-plan-compatible Kokoro voice for spoken replies.
    reference = next((p.get("id") for p in config.get("roster", []) if p.get("key") == "brencis"), None)
    voice = current.get("voice_type") if current else None
    if not voice and reference:
        voice = api.call("/character/get", {"charID": reference}).get("voice_type", "")
    if not isinstance(voice, str) or not voice.startswith("convai-kokoro-"):
        raise RuntimeError("A verified Kokoro reference profile is required to create the interpreter.")
    fields = {"charName": NAME, "voiceType": voice, "backstory": BIO,
              "model_group_name": "fast-gemma-4-31b-it"}
    if not cid:
        cid = api.call("/character/create", fields).get("charID")
        if not isinstance(cid, str) or len(cid) != 36:
            raise RuntimeError("Creation returned no ID. Reconcile before retrying.")
        destination.write_text(json.dumps({"characterId": cid, "name": NAME}, indent=2)+"\n", encoding="utf-8")
    api.call("/character/update", {**fields, "charID": cid, "languageCodes": ["en-US"], "temperature": 0.2})
    actual = api.call("/character/get", {"charID": cid})
    if actual.get("backstory") != BIO or actual.get("character_name") != NAME:
        raise RuntimeError("Profile verification differed.")
    destination.write_text(json.dumps({"characterId": cid, "name": NAME}, indent=2)+"\n", encoding="utf-8")
    print(json.dumps({"verified": True, "characterId": cid, "name": NAME}), flush=True)


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        raise SystemExit(str(exc)) from None
