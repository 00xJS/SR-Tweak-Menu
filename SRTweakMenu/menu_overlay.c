/*
 * SR Tweak Menu - menu overlay (native part, Windows).
 *
 * Lua mods cannot draw text that stays on screen; native mods can, through
 * the loader's overlay_text. This DLL does nothing but display: main.lua
 * writes the menu text into a mailbox in guest memory and this reads it every
 * frame and hands it to overlay_text. All the logic stays in Lua, so the mod
 * works without this file (then each action shows a one-line HUD message
 * instead of the menu).
 *
 * Mailbox (guest address 0x00F00000, inside the loader's committed, zero
 * filled low region that the game never uses on purpose; all words big-endian
 * through the loader's helpers):
 *
 *   +0x00 u32 magic      'SRMU', written here at start (0 = no DLL)
 *   +0x04 u32 version    1
 *   +0x08 u32 caps       bit0 = overlay_text works
 *   +0x0C u32 heartbeat  counts frames, so Lua can tell the DLL is alive
 *   +0x10 u32 lua_seq    Lua bumps it after writing a complete text
 *   +0x14 u32 text_len   bytes of text (0 = hide)
 *   +0x20 u32 ack_seq    the seq this DLL last displayed
 *   +0x30 u32 addons     main.lua: bit0 Weapon switch on, bit1 menu open, bit2 free camera
 *   +0x34 u32 'SRAD'     main.lua, once it writes +0x30 (weapon_switch.dll reads both)
 *   +0x40 ..  text       UTF-8, up to 8 KB
 *
 * Build (the toolchain clang that comes with Saints Reborn):
 *   clang -shared -O2 -I <SaintsReborn>/modding/include -o menu_overlay.dll menu_overlay.c
 */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include "wml.h"

#define MAILBOX 0x00F00000u
#define MAGIC 0x53524D55u /* 'SRMU' */
#define VERSION 1u
#define TEXT_OFFSET 0x40u
#define TEXT_MAX 8192u

static const WmlApi* api;
static const WmlMod* self;
static uint32_t heartbeat, last_seq = 0xFFFFFFFFu;
static char text[TEXT_MAX + 1];
static int shown;

/* The guest region must be committed and writable, or every access crashes. */
static int mailbox_ok(void) {
  void* host = api->guest_pointer(MAILBOX);
  MEMORY_BASIC_INFORMATION info;
  if (!host || !VirtualQuery(host, &info, sizeof info)) return 0;
  if (info.State != MEM_COMMIT) return 0;
  if (!(info.Protect & (PAGE_READWRITE | PAGE_EXECUTE_READWRITE))) return 0;
  uintptr_t end = (uintptr_t)info.BaseAddress + info.RegionSize;
  return end >= (uintptr_t)host + TEXT_OFFSET + TEXT_MAX;
}

static void announce(void) {
  api->write_u32(MAILBOX + 0x00, MAGIC);
  api->write_u32(MAILBOX + 0x04, VERSION);
  api->write_u32(MAILBOX + 0x08, 1);
}

static void on_frame(void* user) {
  (void)user;
  heartbeat++;
  api->write_u32(MAILBOX + 0x0C, heartbeat);
  /* Re-announce now and then in case anything cleared the header. */
  if ((heartbeat & 63) == 0 && api->read_u32(MAILBOX) != MAGIC) announce();
  uint32_t seq = api->read_u32(MAILBOX + 0x10);
  if (seq == last_seq) return;
  last_seq = seq;
  uint32_t len = api->read_u32(MAILBOX + 0x14);
  if (len > TEXT_MAX) len = TEXT_MAX;
  if (len == 0) {
    if (shown) { api->overlay_text(""); shown = 0; }
  } else {
    /* Guest bytes are plain UTF-8; no byte order to undo. */
    memcpy(text, (const char*)api->guest_pointer(MAILBOX + TEXT_OFFSET), len);
    text[len] = 0;
    api->overlay_text(text);
    shown = 1;
  }
  api->write_u32(MAILBOX + 0x20, seq);
}

WML_EXPORT int wml_mod_init(const WmlApi* loader, const WmlMod* mod) {
  if (!loader || loader->version != WML_API_VERSION || loader->size < sizeof(WmlApi) || !loader->overlay_text) return 1;
  api = loader;
  self = mod;
  if (!mailbox_ok()) {
    api->log(self, "menu overlay: mailbox memory at 0x00F00000 is not available; the menu will use HUD messages instead.");
    return 0;
  }
  announce();
  api->on_frame(on_frame, 0);
  api->log(self, "menu overlay loaded (mailbox 0x00F00000).");
  return 0;
}
