# omarchy-r2drop

An Omarchy port of R2Drop: a CLI and Quickshell bar widget that uploads screenshots and images to a Cloudflare R2 bucket and copies the public link to your clipboard.

## Install

### Bar plugin + CLI

Install the plugin with `omarchy plugin add`:

```bash
omarchy plugin add https://github.com/yongkang-yang/omarchy-r2drop.git --enable
~/.config/omarchy/plugins/ykyan.r2drop/install.sh
```

Or from a local checkout:

```bash
./install.sh
ln -s "$(pwd)" ~/.config/omarchy/plugins/ykyan.r2drop
omarchy-shell shell rescanPlugins
omarchy plugin enable ykyan.r2drop
```

Optional file picker dependency (for `r2drop pick`):

```bash
omarchy pkg add zenity
```

## Configuration

Edit `~/.config/r2drop/config.env` (created by `./install.sh` from `config.env.example`):

```ini
CLOUDFLARE_ACCOUNT_ID="your-account-id"
CLOUDFLARE_R2_BUCKET="your-bucket"
CLOUDFLARE_R2_PUBLIC_URL="https://img.example.com"
R2DROP_FORMAT="markdown"
```

Supported `R2DROP_FORMAT` values:
- `url` — `https://img.example.com/2026/09/shot-a8f31c.png`
- `markdown` (default) — `![](https://img.example.com/2026/09/shot-a8f31c.png)`
- `html` — `<img src="https://img.example.com/2026/09/shot-a8f31c.png">`
- `markdown-filename` — `![shot](https://img.example.com/2026/09/shot-a8f31c.png)`

### Secrets

Provide S3 API credentials via environment variables:
- `CLOUDFLARE_R2_ACCESS_KEY_ID`
- `CLOUDFLARE_R2_SECRET_ACCESS_KEY`

If those variables are unset and `ykcred` is on `PATH`, `r2drop` automatically re-execs under `ykcred run image-hosting -- ...`.

## Suggested Hyprland bindings

Add to `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + SHIFT + S", "Capture & upload to R2", "r2drop capture")
o.bind("SUPER + SHIFT + U", "Upload clipboard image to R2", "r2drop clipboard")
o.bind("SUPER + SHIFT + O", "Pick & upload image to R2", "r2drop pick")
```

## Commands

- `r2drop capture` — select a screen region (`slurp` + `grim`), upload to R2, and copy the link.
- `r2drop clipboard` — upload an `image/*` or `file://` image URI list from the Wayland clipboard and replace the clipboard with the link(s).
- `r2drop pick` — pick one or more images via `zenity` (with an optional custom name for a single file) and upload.
- `r2drop upload [--name NAME] FILE...` — upload one or more image files directly.
- `r2drop recent [--json] [N]` — list the last `N` (default 20) uploads, newest first.
- `r2drop copy KEY` — re-copy a history entry's link in `R2DROP_FORMAT`.
- `omarchy-shell ykyan.r2drop refresh` — refresh the bar widget's recent uploads list over shell IPC.

## License

[MIT](LICENSE)
