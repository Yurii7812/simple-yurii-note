#!/usr/bin/env python3
"""スキャン画像にフォルゲゼッテルIDを付ける GUI（simple_yurii_note 用）。

`\\f`（:SimpleScan）から起動される。流れ::

    1. スキャン画像のあるフォルダを選ぶ
    2. 画像を見ながら ID を手入力（→=次の連番 / ↓=子ID / ↑=直前を編集 /
       Space=手入力 / ←=取り消し。ドラッグやボタンで順番も変更できる）
    3. 終わったら「移動して終了」または全枚数の完了で、画像を
       `--dest`（今開いている Index のフォルダ）へ `<ID>.<拡張子>` として移し、
       タイムスタンプ名ノートを作って paper_pkm.regen（Index・グループ・
       Folgezettel-Index 再生成＋SYN同期）まで行う。

使い方::

    folgezettel_scan.py --root VAULT --dest MOVE_DIR
"""
from __future__ import annotations

import json
import shutil
import subprocess
import sys
import tkinter as tk
import traceback
from dataclasses import asdict, dataclass
from datetime import datetime
from pathlib import Path
from tkinter import filedialog, font as tkfont, messagebox, ttk
from typing import Optional

try:
    from PIL import Image, ImageOps, ImageTk
except ImportError:
    root = tk.Tk()
    root.withdraw()
    messagebox.showerror(
        "Pillowが必要です",
        "画像表示に必要なPillowが入っていません。\n\npython3 -m pip install Pillow",
    )
    raise

sys.path.insert(0, str(Path(__file__).resolve().parent))
import paper_pkm as pp  # noqa: E402

APP_TITLE = "フォルゲゼッテル番号付け"
PROJECT_FILE = ".folgezettel_project.json"
SETTINGS_PATH = Path.home() / ".config" / "simple_yurii_note" / "folgezettel_scan.json"

UI_FONT_CANDIDATES = (
    "Noto Sans CJK JP",
    "Noto Sans JP",
    "Source Han Sans JP",
    "Yu Gothic UI",
    "Meiryo",
    "DejaVu Sans",
    "Helvetica",
)
MONO_FONT_CANDIDATES = (
    "Noto Sans Mono CJK JP",
    "DejaVu Sans Mono",
    "Liberation Mono",
    "Consolas",
    "Courier New",
)

COL_BG = "#f4f5f7"
COL_CARD = "#ffffff"
COL_BORDER = "#d0d4da"
COL_TEXT = "#1c1f23"
COL_MUTED = "#6a7078"
COL_ACCENT = "#1a6fd4"
COL_ACCENT_TEXT = "#ffffff"
COL_CANVAS = "#202020"
COL_PREVIEW = "#2b2b2b"
COL_DONE = "#1a7f37"
COL_PENDING = "#9aa0a6"

FONT_SIZES = {"title": 16, "section": 11, "body": 10, "small": 9,
              "input": 16, "progress": 20}


@dataclass
class ImageItem:
    original_name: str
    current_name: str
    folgezettel_id: Optional[str] = None
    processed: bool = False

    def current_path(self, folder: Path) -> Path:
        return folder / self.current_name


def pick_font(widget: tk.Misc, candidates: tuple[str, ...], fallback: str) -> str:
    try:
        available = {name.casefold(): name for name in tkfont.families(widget)}
    except tk.TclError:
        return fallback
    for candidate in candidates:
        found = available.get(candidate.casefold())
        if found:
            return found
    return fallback


def pick_directory(title: str, initialdir: Optional[str] = None) -> Optional[str]:
    """kdialog → zenity → Tk の順で使えるフォルダ選択ダイアログ。"""
    initial = initialdir if initialdir and Path(initialdir).is_dir() else str(Path.home())
    if shutil.which("kdialog"):
        try:
            proc = subprocess.run(
                ["kdialog", "--title", title, "--getexistingdirectory", initial],
                capture_output=True, text=True,
            )
        except OSError:
            proc = None
        if proc is not None:
            if proc.returncode == 0:
                return proc.stdout.strip() or None
            if proc.returncode == 1:
                return None
    if shutil.which("zenity"):
        try:
            proc = subprocess.run(
                ["zenity", "--file-selection", "--directory", "--title", title,
                 f"--filename={initial.rstrip('/')}/"],
                capture_output=True, text=True,
            )
        except OSError:
            proc = None
        if proc is not None:
            if proc.returncode == 0:
                return proc.stdout.strip() or None
            if proc.returncode in (1, 5):
                return None
    selected = filedialog.askdirectory(
        title=title, initialdir=initial if Path(initial).is_dir() else None
    )
    return selected or None


def load_settings() -> dict:
    try:
        return json.loads(SETTINGS_PATH.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}


def save_settings(data: dict) -> None:
    try:
        SETTINGS_PATH.parent.mkdir(parents=True, exist_ok=True)
        SETTINGS_PATH.write_text(
            json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8"
        )
    except OSError:
        pass


class ScanApp:
    def __init__(self, root: tk.Tk, vault_root: Path, dest: Path):
        self.root = root
        self.vault_root = Path(vault_root).resolve()
        self.dest = Path(dest).resolve()
        self.root.title(APP_TITLE)
        self.root.geometry("1280x820")
        self.root.minsize(980, 680)

        self.folder: Optional[Path] = None
        self.items: list[ImageItem] = []
        self.current_index = 0
        self.undo_stack: list[dict] = []
        self.drag_iid: Optional[str] = None
        self.drag_moved = False
        self.thumbnail_refs: dict[str, ImageTk.PhotoImage] = {}
        self.preview_image: Optional[ImageTk.PhotoImage] = None
        self.full_image: Optional[Image.Image] = None
        self.zoom = 1.0
        self.input_active = False
        self.moving = False

        self.sort_var = tk.StringVar(value="ファイル名（自然順・昇順）")
        self.folder_var = tk.StringVar(value="フォルダ未選択")
        self.dest_var = tk.StringVar(value=str(self.dest))
        self.status_var = tk.StringVar(value="スキャン画像のフォルダを選択してください")
        self.progress_var = tk.StringVar(value="")
        self.previous_id_var = tk.StringVar(value="なし")
        self.current_file_var = tk.StringVar(value="")
        self.input_var = tk.StringVar(value="")

        self.ui_font = pick_font(self.root, UI_FONT_CANDIDATES, "TkDefaultFont")
        self.mono_font = pick_font(self.root, MONO_FONT_CANDIDATES, "TkFixedFont")

        self.settings = load_settings()
        self._setup_styles()
        self._build_setup_frame()
        self._build_naming_frame()
        self.show_setup()
        self.root.protocol("WM_DELETE_WINDOW", self.on_close)
        self._refresh_recent_buttons()

        last_folder = self.settings.get("last_folder")
        fallback = Path(last_folder) if last_folder and Path(last_folder).is_dir() else None
        self.root.after(120, lambda: self.prompt_initial_folder(fallback))

    def set_maximized(self):
        """ウィンドウを最大化する（全画面ではなく、タイトルバーは残す）。"""
        try:
            self.root.state("zoomed")
            return
        except tk.TclError:
            pass
        try:
            self.root.attributes("-zoomed", True)
            return
        except tk.TclError:
            pass
        width = self.root.winfo_screenwidth()
        height = self.root.winfo_screenheight()
        self.root.geometry(f"{width}x{height}+0+0")

    def prompt_initial_folder(self, fallback: Optional[Path]):
        """起動直後にスキャン画像フォルダの選択を出す（キャンセルで前回を使う）。"""
        initial = str(fallback) if fallback else str(Path.home())
        selected = pick_directory("スキャン画像フォルダを選択", initial)
        if selected:
            self.load_folder(Path(selected))
        elif fallback is not None:
            self.load_folder(fallback, ask_resume=False)

    # ---------- 見た目 ----------
    def _setup_styles(self):
        style = ttk.Style(self.root)
        for theme in ("clam", "alt", "default"):
            if theme in style.theme_names():
                style.theme_use(theme)
                break
        body = FONT_SIZES["body"]
        small = FONT_SIZES["small"]
        try:
            self.root.configure(background=COL_BG)
        except tk.TclError:
            pass
        style.configure(".", font=(self.ui_font, body), background=COL_BG, foreground=COL_TEXT)
        style.configure("TFrame", background=COL_BG)
        style.configure("Card.TFrame", background=COL_CARD)
        style.configure("TLabel", background=COL_BG, foreground=COL_TEXT, font=(self.ui_font, body))
        style.configure("Card.TLabel", background=COL_CARD, foreground=COL_TEXT, font=(self.ui_font, body))
        style.configure("CardMuted.TLabel", background=COL_CARD, foreground=COL_MUTED, font=(self.ui_font, small))
        style.configure("Title.TLabel", background=COL_BG, foreground=COL_TEXT, font=(self.ui_font, FONT_SIZES["title"], "bold"))
        style.configure("Subtitle.TLabel", background=COL_BG, foreground=COL_MUTED, font=(self.ui_font, small))
        style.configure("Muted.TLabel", background=COL_BG, foreground=COL_MUTED, font=(self.ui_font, small))
        style.configure("Mono.TLabel", background=COL_BG, foreground=COL_TEXT, font=(self.mono_font, body, "bold"))
        style.configure("MonoCard.TLabel", background=COL_CARD, foreground=COL_TEXT, font=(self.mono_font, body, "bold"))
        style.configure("Preview.TLabel", background=COL_CARD, foreground=COL_ACCENT, font=(self.mono_font, small, "bold"))
        style.configure("ProgressNum.TLabel", background=COL_CARD, foreground=COL_ACCENT, font=(self.ui_font, FONT_SIZES["progress"], "bold"))
        style.configure("Chip.TLabel", background="#e8ebf0", foreground=COL_TEXT,
                        font=(self.mono_font, small, "bold"), padding=(6, 1),
                        relief="solid", borderwidth=1)
        style.configure("TButton", padding=(10, 5), font=(self.ui_font, body))
        style.configure("Accent.TButton", font=(self.ui_font, body, "bold"),
                        foreground=COL_ACCENT_TEXT, background=COL_ACCENT,
                        padding=(18, 8), borderwidth=0)
        style.map("Accent.TButton",
                  background=[("active", "#155bb0"), ("pressed", "#0f4d99"), ("disabled", "#a9c5e8")],
                  foreground=[("disabled", "#eef4fb")])
        style.configure("Card.TLabelframe", background=COL_CARD, bordercolor=COL_BORDER,
                        relief="solid", borderwidth=1)
        style.configure("Card.TLabelframe.Label", background=COL_CARD, foreground=COL_ACCENT,
                        font=(self.ui_font, FONT_SIZES["section"], "bold"))
        style.configure("Treeview", rowheight=52, font=(self.ui_font, body),
                        background=COL_CARD, fieldbackground=COL_CARD,
                        foreground=COL_TEXT, borderwidth=0)
        style.configure("Treeview.Heading", font=(self.ui_font, body, "bold"), padding=(4, 6))
        style.map("Treeview", background=[("selected", COL_ACCENT)],
                  foreground=[("selected", COL_ACCENT_TEXT)])
        style.configure("TEntry", fieldbackground="#ffffff", padding=4)
        style.configure("TCombobox", padding=3)
        style.configure("Horizontal.TProgressbar", background=COL_ACCENT,
                        troughcolor="#dde2e8", borderwidth=0)

    def _key_chip(self, parent, key: str, desc: str):
        chip = ttk.Frame(parent, style="Card.TFrame")
        ttk.Label(chip, text=key, style="Chip.TLabel").pack(side="left")
        ttk.Label(chip, text=desc, style="CardMuted.TLabel").pack(side="left", padx=(5, 14))
        return chip

    # ---------- セットアップ画面 ----------
    def _build_setup_frame(self):
        self.setup_frame = ttk.Frame(self.root, padding=14)

        heading = ttk.Frame(self.setup_frame)
        heading.pack(fill="x", pady=(0, 10))
        ttk.Label(heading, text=APP_TITLE, style="Title.TLabel").pack(anchor="w")
        ttk.Label(
            heading,
            text="画像の順番を整えてから ID を付けます。まずスキャン画像のフォルダを選んでください。",
            style="Subtitle.TLabel",
        ).pack(anchor="w", pady=(2, 0))

        dest_card = ttk.Labelframe(self.setup_frame, text="移動先（今開いている Index のフォルダ）",
                                   style="Card.TLabelframe", padding=12)
        dest_card.pack(fill="x")
        ttk.Label(dest_card, textvariable=self.dest_var, style="MonoCard.TLabel").pack(anchor="w")

        folder_card = ttk.Labelframe(self.setup_frame, text="スキャン画像フォルダ",
                                     style="Card.TLabelframe", padding=12)
        folder_card.pack(fill="x", pady=(10, 0))
        folder_row = ttk.Frame(folder_card, style="Card.TFrame")
        folder_row.pack(fill="x")
        ttk.Button(folder_row, text="フォルダを選択", command=self.choose_folder).pack(side="left")
        ttk.Label(folder_row, textvariable=self.folder_var, style="CardMuted.TLabel").pack(
            side="left", padx=10, fill="x", expand=True)
        recent_row = ttk.Frame(folder_card, style="Card.TFrame")
        recent_row.pack(fill="x", pady=(8, 0))
        ttk.Label(recent_row, text="最近のフォルダ:", style="CardMuted.TLabel").pack(side="left")
        self.recent_bar = ttk.Frame(recent_row, style="Card.TFrame")
        self.recent_bar.pack(side="left", fill="x", expand=True)

        order_card = ttk.Labelframe(self.setup_frame, text="並び替えと順番の微調整",
                                    style="Card.TLabelframe", padding=12)
        order_card.pack(fill="x", pady=(10, 0))
        controls = ttk.Frame(order_card, style="Card.TFrame")
        controls.pack(fill="x")
        ttk.Label(controls, text="自動並び替え:", style="Card.TLabel").pack(side="left")
        ttk.Combobox(
            controls, textvariable=self.sort_var, state="readonly", width=26,
            values=[
                "ファイル名（自然順・昇順）",
                "ファイル名（自然順・降順）",
                "更新日時（古い順）",
                "更新日時（新しい順）",
            ],
        ).pack(side="left", padx=6)
        ttk.Button(controls, text="適用", command=self.apply_sort).pack(side="left")
        ttk.Separator(controls, orient="vertical").pack(side="left", fill="y", padx=12)
        ttk.Label(controls, text="選択した画像:", style="Card.TLabel").pack(side="left")
        ttk.Button(controls, text="一つ上へ", command=lambda: self.move_selected(-1)).pack(side="left", padx=(6, 2))
        ttk.Button(controls, text="一つ下へ", command=lambda: self.move_selected(1)).pack(side="left", padx=2)
        ttk.Button(controls, text="除外", command=self.exclude_selected).pack(side="left", padx=(10, 0))

        action_row = ttk.Frame(self.setup_frame)
        action_row.pack(fill="x", pady=(12, 8))
        ttk.Button(action_row, text="名前付けを開始", style="Accent.TButton",
                   command=self.start_naming).pack(side="left")
        ttk.Button(action_row, text="閉じる", command=self.on_close).pack(side="left", padx=(8, 0))
        ttk.Button(action_row, text="名前付け済みを移動して終了",
                   command=lambda: self.move_processed(auto=False)).pack(side="right")

        body = ttk.Panedwindow(self.setup_frame, orient="horizontal")
        body.pack(fill="both", expand=True)
        list_frame = ttk.Frame(body)
        preview_frame = ttk.Frame(body, padding=(10, 0, 0, 0))
        body.add(list_frame, weight=3)
        body.add(preview_frame, weight=2)

        self.tree = ttk.Treeview(
            list_frame, columns=("order", "name", "id", "modified"),
            show="tree headings", selectmode="extended",
        )
        self.tree.heading("#0", text="画像")
        self.tree.heading("order", text="順番")
        self.tree.heading("name", text="ファイル名")
        self.tree.heading("id", text="ID")
        self.tree.heading("modified", text="更新日時")
        self.tree.column("#0", width=100, stretch=False)
        self.tree.column("order", width=56, anchor="center", stretch=False)
        self.tree.column("name", width=320)
        self.tree.column("id", width=90, anchor="center", stretch=False)
        self.tree.column("modified", width=135, stretch=False)
        self.tree.tag_configure("done", foreground=COL_DONE)
        self.tree.tag_configure("todo", foreground=COL_PENDING)
        scrollbar = ttk.Scrollbar(list_frame, orient="vertical", command=self.tree.yview)
        self.tree.configure(yscrollcommand=scrollbar.set)
        self.tree.pack(side="left", fill="both", expand=True)
        scrollbar.pack(side="right", fill="y")
        self.tree.bind("<<TreeviewSelect>>", self.on_tree_select)
        self.tree.bind("<ButtonPress-1>", self.on_drag_start, add=True)
        self.tree.bind("<B1-Motion>", self.on_drag_motion, add=True)
        self.tree.bind("<ButtonRelease-1>", self.on_drag_end, add=True)

        ttk.Label(preview_frame, text="選択画像の確認", style="Mono.TLabel").pack(anchor="w")
        self.setup_preview = tk.Canvas(preview_frame, background=COL_PREVIEW,
                                       highlightthickness=0, highlightbackground=COL_BORDER)
        self.setup_preview.pack(fill="both", expand=True, pady=(6, 0))
        ttk.Label(self.setup_frame,
                  text="ヒント: 行をドラッグ＆ドロップ、またはボタンで順番を変更できます。",
                  style="Muted.TLabel").pack(anchor="w", pady=(8, 0))
        ttk.Label(self.setup_frame, textvariable=self.status_var, style="Mono.TLabel").pack(
            anchor="w", pady=(2, 0))

    # ---------- 名前付け画面 ----------
    def _build_naming_frame(self):
        self.naming_frame = ttk.Frame(self.root, padding=12)
        header_card = ttk.Labelframe(self.naming_frame, style="Card.TLabelframe", padding=(14, 8))
        header_card.pack(fill="x")
        header = ttk.Frame(header_card, style="Card.TFrame")
        header.pack(fill="x")

        progress_box = ttk.Frame(header, style="Card.TFrame")
        progress_box.pack(side="left")
        ttk.Label(progress_box, textvariable=self.progress_var, style="ProgressNum.TLabel").pack(anchor="w")
        self.naming_progress = ttk.Progressbar(progress_box, orient="horizontal", length=190, mode="determinate")
        self.naming_progress.pack(anchor="w", pady=(3, 0))
        ttk.Label(progress_box, textvariable=self.current_file_var, style="CardMuted.TLabel").pack(
            anchor="w", pady=(3, 0))

        info_box = ttk.Frame(header, style="Card.TFrame")
        info_box.pack(side="left", padx=(26, 0), anchor="n")
        ttk.Label(info_box, text="直前のID", style="CardMuted.TLabel").pack(anchor="w")
        ttk.Label(info_box, textvariable=self.previous_id_var, style="MonoCard.TLabel").pack(anchor="w")
        ttk.Label(info_box, text="移動先", style="CardMuted.TLabel").pack(anchor="w", pady=(6, 0))
        ttk.Label(info_box, textvariable=self.dest_var, style="MonoCard.TLabel").pack(anchor="w")

        ttk.Button(header, text="移動して終了", style="Accent.TButton",
                   command=lambda: self.move_processed(auto=False)).pack(side="right", anchor="n")
        ttk.Button(header, text="セットアップに戻る", command=self.show_setup).pack(
            side="right", padx=(0, 8), anchor="n")

        self.image_canvas = tk.Canvas(self.naming_frame, background=COL_CANVAS, highlightthickness=0)
        self.image_canvas.pack(fill="both", expand=True, pady=10)
        self.image_canvas.bind("<Configure>", lambda e: self.render_current_image())
        self.image_canvas.bind("<MouseWheel>", self.on_mousewheel)

        self.input_holder = ttk.Frame(self.naming_frame, style="Card.TFrame", padding=12)
        self.input_frame = ttk.Frame(self.input_holder, style="Card.TFrame")
        ttk.Label(self.input_frame, text="ID:", style="Card.TLabel").pack(side="left")
        self.input_entry = ttk.Entry(self.input_frame, textvariable=self.input_var,
                                     font=(self.mono_font, FONT_SIZES["input"]), width=24)
        self.input_entry.pack(side="left", padx=8)
        ttk.Label(self.input_frame, text="Enter で確定 ／ Esc でキャンセル",
                  style="CardMuted.TLabel").pack(side="left")
        self.input_entry.bind("<Return>", self.confirm_manual_id)
        self.input_entry.bind("<Escape>", self.cancel_input)

        self.naming_help = ttk.Frame(self.naming_frame, style="Card.TFrame", padding=(12, 8))
        self.naming_help.pack(fill="x", pady=(8, 0))
        legend = ttk.Frame(self.naming_help, style="Card.TFrame")
        legend.pack(anchor="center")
        row = ttk.Frame(legend, style="Card.TFrame")
        row.pack(anchor="center")
        for key, desc in (("→", "次の連番"), ("↓", "子ID"), ("↑", "直前IDを編集"),
                          ("Space", "手入力"), ("←", "取り消し")):
            self._key_chip(row, key, desc).pack(side="left")
        ttk.Label(self.naming_frame, textvariable=self.status_var, style="Mono.TLabel").pack(
            anchor="center", pady=(6, 0))

    # ---------- フォルダ ----------
    def choose_folder(self):
        initial = self.settings.get("last_folder") or str(Path.home())
        selected = pick_directory("スキャン画像フォルダを選択", initial)
        if selected:
            self.load_folder(Path(selected))

    def _add_recent_folder(self, folder: Path):
        target = str(folder)
        recent = [p for p in self.settings.get("recent_folders", []) if p != target]
        recent.insert(0, target)
        self.settings["recent_folders"] = recent[:5]

    def _refresh_recent_buttons(self):
        for child in self.recent_bar.winfo_children():
            child.destroy()
        recent = [p for p in self.settings.get("recent_folders", []) if Path(p).is_dir()]
        if not recent:
            ttk.Label(self.recent_bar, text="（まだありません）", style="CardMuted.TLabel").pack(side="left")
            return
        for path in recent:
            ttk.Button(self.recent_bar, text=Path(path).name or path,
                       command=lambda p=path: self.load_folder(Path(p))).pack(side="left", padx=(0, 6))

    def load_folder(self, folder: Path, ask_resume: bool = True):
        self.folder = Path(folder)
        self.folder_var.set(str(folder))
        self.settings["last_folder"] = str(folder)
        self._add_recent_folder(folder)
        save_settings(self.settings)
        self._refresh_recent_buttons()

        project_path = folder / PROJECT_FILE
        loaded = False
        if project_path.exists():
            use = True
            if ask_resume:
                use = messagebox.askyesno(
                    "前回の作業データ",
                    "このフォルダには前回の作業データがあります。再開しますか？\n\n"
                    "「いいえ」を選ぶと現在のファイルから新しく一覧を作ります。",
                )
            if use:
                loaded = self.load_project(project_path)
        if not loaded:
            paths = [p for p in folder.iterdir()
                     if p.is_file() and p.suffix.lower() in pp.IMAGE_EXTENSIONS]
            paths.sort(key=lambda p: pp.natural_key(p.name))
            self.items = [ImageItem(original_name=p.name, current_name=p.name) for p in paths]
            self.current_index = 0
            self.undo_stack.clear()
        self.refresh_tree()
        self.status_var.set(f"{len(self.items)}枚を読み込みました")
        # フォルダ選択後は最大化して作業する
        self.set_maximized()

    def project_path(self) -> Optional[Path]:
        return self.folder / PROJECT_FILE if self.folder else None

    def save_project(self):
        if not self.folder:
            return
        data = {
            "version": 1,
            "folder": str(self.folder),
            "current_index": self.current_index,
            "items": [asdict(item) for item in self.items],
            "undo_stack": self.undo_stack,
        }
        try:
            self.project_path().write_text(
                json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
        except OSError as exc:
            self.status_var.set(f"作業データを保存できませんでした: {exc}")

    def load_project(self, project_path: Path) -> bool:
        try:
            data = json.loads(project_path.read_text(encoding="utf-8"))
            items = [ImageItem(**item) for item in data.get("items", [])]
            if not items:
                return False
            self.items = items
            self.current_index = int(data.get("current_index", 0))
            self.undo_stack = data.get("undo_stack", [])
            return True
        except (OSError, json.JSONDecodeError, TypeError, ValueError) as exc:
            messagebox.showwarning("作業データを読み込めません", str(exc))
            return False

    # ---------- 一覧 ----------
    def refresh_tree(self):
        self.thumbnail_refs.clear()
        for iid in self.tree.get_children():
            self.tree.delete(iid)
        if not self.folder:
            return
        for idx, item in enumerate(self.items):
            path = item.current_path(self.folder)
            stat_text = ""
            image_ref = None
            try:
                st = path.stat()
                stat_text = datetime.fromtimestamp(st.st_mtime).strftime("%Y-%m-%d %H:%M")
                image_ref = self.make_thumbnail(path, (86, 66))
            except OSError:
                pass
            iid = str(idx)
            self.tree.insert(
                "", "end", iid=iid, text="", image=image_ref,
                values=(idx + 1, item.current_name, item.folgezettel_id or "",
                        stat_text),
                tags=("done" if item.processed else "todo",),
            )
            if image_ref:
                self.thumbnail_refs[iid] = image_ref

    def make_thumbnail(self, path: Path, size: tuple[int, int]) -> Optional[ImageTk.PhotoImage]:
        try:
            with Image.open(path) as image:
                image = ImageOps.exif_transpose(image).convert("RGB")
                image.thumbnail(size, Image.Resampling.LANCZOS)
                return ImageTk.PhotoImage(image.copy())
        except Exception:
            return None

    def apply_sort(self):
        if not self.folder or not self.items:
            return
        mode = self.sort_var.get()

        def safe_stat(item: ImageItem):
            try:
                return item.current_path(self.folder).stat().st_mtime
            except OSError:
                return 0.0

        if mode == "ファイル名（自然順・昇順）":
            self.items.sort(key=lambda i: pp.natural_key(i.current_name))
        elif mode == "ファイル名（自然順・降順）":
            self.items.sort(key=lambda i: pp.natural_key(i.current_name), reverse=True)
        elif mode == "更新日時（古い順）":
            self.items.sort(key=safe_stat)
        elif mode == "更新日時（新しい順）":
            self.items.sort(key=safe_stat, reverse=True)
        self.current_index = self.first_unprocessed_index()
        self.refresh_tree()
        self.save_project()

    def selected_indices(self) -> list[int]:
        result = []
        for iid in self.tree.selection():
            try:
                result.append(int(iid))
            except ValueError:
                continue
        return sorted(result)

    def move_selected(self, delta: int):
        indices = self.selected_indices()
        if len(indices) != 1:
            self.status_var.set("一つの画像を選択してください")
            return
        i = indices[0]
        j = i + delta
        if not (0 <= j < len(self.items)):
            return
        self.items[i], self.items[j] = self.items[j], self.items[i]
        self.refresh_tree()
        self.tree.selection_set(str(j))
        self.tree.see(str(j))
        self.save_project()

    def exclude_selected(self):
        indices = self.selected_indices()
        if not indices:
            return
        if any(self.items[i].processed for i in indices):
            messagebox.showwarning("除外できません", "名前付け済みの画像は除外できません。先に取り消してください。")
            return
        if not messagebox.askyesno("一覧から除外",
                                   f"選択した{len(indices)}枚を今回の作業一覧から除外しますか？\nファイル自体は削除しません。"):
            return
        for i in reversed(indices):
            self.items.pop(i)
        self.current_index = self.first_unprocessed_index()
        self.refresh_tree()
        self.save_project()

    def on_tree_select(self, _event=None):
        indices = self.selected_indices()
        if not indices or not self.folder:
            return
        path = self.items[indices[0]].current_path(self.folder)
        try:
            with Image.open(path) as image:
                image = ImageOps.exif_transpose(image).convert("RGB")
                width = max(self.setup_preview.winfo_width(), 400)
                height = max(self.setup_preview.winfo_height(), 300)
                image.thumbnail((width - 20, height - 20), Image.Resampling.LANCZOS)
                self.preview_image = ImageTk.PhotoImage(image.copy())
            self.setup_preview.delete("all")
            self.setup_preview.create_image(width // 2, height // 2,
                                            image=self.preview_image, anchor="center")
        except Exception as exc:
            self.setup_preview.delete("all")
            self.setup_preview.create_text(20, 20, text=f"画像を表示できません\n{exc}",
                                           anchor="nw", fill="white")

    def on_drag_start(self, event):
        self.drag_iid = self.tree.identify_row(event.y)
        self.drag_moved = False
        if self.drag_iid:
            self.tree.configure(cursor="fleur")

    def on_drag_motion(self, event):
        if not self.drag_iid:
            return
        target = self.tree.identify_row(event.y)
        if not target or target == self.drag_iid:
            return
        target_index = self.tree.index(target)
        bbox = self.tree.bbox(target)
        if bbox and event.y > bbox[1] + bbox[3] // 2:
            target_index += 1
        current = self.tree.index(self.drag_iid)
        if target_index > current:
            target_index -= 1
        if target_index != current:
            self.tree.move(self.drag_iid, "", target_index)
            self.drag_moved = True

    def on_drag_end(self, _event):
        moved_iid = self.drag_iid
        self.drag_iid = None
        self.tree.configure(cursor="")
        if not moved_iid or not self.drag_moved:
            return
        old_items = self.items[:]
        new_items = []
        for iid in self.tree.get_children():
            try:
                new_items.append(old_items[int(iid)])
            except (ValueError, IndexError):
                pass
        if len(new_items) == len(old_items):
            self.items = new_items
            self.refresh_tree()
            self.save_project()
        self.drag_moved = False

    # ---------- 名前付け ----------
    def show_setup(self):
        self.unbind_naming_keys()
        self.naming_frame.pack_forget()
        self.setup_frame.pack(fill="both", expand=True)

    def start_naming(self):
        if not self.folder or not self.items:
            messagebox.showwarning("画像がありません", "先にスキャン画像のフォルダを選択してください。")
            return
        self.current_index = self.first_unprocessed_index()
        if self.current_index >= len(self.items):
            messagebox.showinfo("完了", "すべての画像に ID が付いています。")
            return
        self.setup_frame.pack_forget()
        self.naming_frame.pack(fill="both", expand=True)
        self.input_active = False
        self.hide_input()
        self.bind_naming_keys()
        self.load_current_image()

    def first_unprocessed_index(self) -> int:
        for i, item in enumerate(self.items):
            if not item.processed:
                return i
        return len(self.items)

    def bind_naming_keys(self):
        self.root.bind("<Right>", self.on_right)
        self.root.bind("<Down>", self.on_down)
        self.root.bind("<Up>", self.on_up)
        self.root.bind("<Left>", self.on_left)
        self.root.bind("<space>", self.on_space)
        self.root.bind("<Escape>", self.on_escape_global)

    def unbind_naming_keys(self):
        for sequence in ("<Right>", "<Down>", "<Up>", "<Left>", "<space>", "<Escape>"):
            self.root.unbind(sequence)

    def previous_id(self) -> Optional[str]:
        if self.current_index <= 0:
            return None
        for i in range(self.current_index - 1, -1, -1):
            if self.items[i].processed and self.items[i].folgezettel_id:
                return self.items[i].folgezettel_id
        return None

    def load_current_image(self):
        if not self.folder:
            return
        if self.current_index >= len(self.items):
            self.finish_work()
            return
        item = self.items[self.current_index]
        path = item.current_path(self.folder)
        self.progress_var.set(f"{self.current_index + 1} / {len(self.items)}")
        self.naming_progress.configure(maximum=max(len(self.items), 1), value=self.current_index)
        self.current_file_var.set(f"元: {item.original_name}　現在: {item.current_name}")
        self.previous_id_var.set(self.previous_id() or "なし")
        self.status_var.set("画像内のIDを確認してください")
        self.zoom = 1.0
        try:
            with Image.open(path) as image:
                self.full_image = ImageOps.exif_transpose(image).convert("RGB")
            self.render_current_image()
        except Exception as exc:
            self.full_image = None
            self.image_canvas.delete("all")
            self.image_canvas.create_text(20, 20, text=f"画像を表示できません\n{exc}",
                                          anchor="nw", fill="white")

    def render_current_image(self):
        if self.full_image is None:
            return
        canvas_w = max(self.image_canvas.winfo_width(), 200)
        canvas_h = max(self.image_canvas.winfo_height(), 200)
        fit = min((canvas_w - 20) / self.full_image.width,
                  (canvas_h - 20) / self.full_image.height)
        scale = max(0.05, fit * self.zoom)
        width = max(1, int(self.full_image.width * scale))
        height = max(1, int(self.full_image.height * scale))
        displayed = self.full_image.resize((width, height), Image.Resampling.LANCZOS)
        self.preview_image = ImageTk.PhotoImage(displayed)
        self.image_canvas.delete("all")
        self.image_canvas.create_image(canvas_w // 2, canvas_h // 2,
                                       image=self.preview_image, anchor="center")

    def on_mousewheel(self, event):
        if event.delta > 0:
            self.zoom = min(8.0, self.zoom * 1.15)
        else:
            self.zoom = max(0.2, self.zoom / 1.15)
        self.render_current_image()

    def on_right(self, _event=None):
        if self.input_active:
            return
        previous = self.previous_id()
        if previous is None:
            self.status_var.set("最初の画像はSpaceキーでIDを入力してください")
            return "break"
        try:
            self.commit_id(pp.next_sibling_id(previous))
        except ValueError as exc:
            self.status_var.set(str(exc))
        return "break"

    def on_down(self, _event=None):
        if self.input_active:
            return
        previous = self.previous_id()
        if previous is None:
            self.status_var.set("最初の画像はSpaceキーでIDを入力してください")
            return "break"
        try:
            self.commit_id(pp.child_id(previous))
        except ValueError as exc:
            self.status_var.set(str(exc))
        return "break"

    def on_up(self, _event=None):
        if self.input_active:
            return
        self.show_input(self.previous_id() or "")
        return "break"

    def on_space(self, _event=None):
        if self.input_active:
            return
        self.show_input("")
        return "break"

    def on_left(self, _event=None):
        if self.input_active:
            return
        self.undo_last()
        return "break"

    def on_escape_global(self, _event=None):
        if self.input_active:
            self.cancel_input()
        return "break"

    def show_input(self, value: str):
        self.input_active = True
        self.input_var.set(value)
        self.input_holder.pack(fill="x", pady=(6, 4), before=self.naming_help)
        self.input_frame.pack(fill="x", pady=2)
        self.input_entry.focus_set()
        self.input_entry.icursor(tk.END)
        self.status_var.set("IDを入力または修正してEnterで確定します")

    def hide_input(self):
        self.input_frame.pack_forget()
        self.input_holder.pack_forget()
        self.input_active = False
        self.root.focus_set()

    def cancel_input(self, _event=None):
        self.hide_input()
        self.status_var.set("入力をキャンセルしました")
        return "break"

    def confirm_manual_id(self, _event=None):
        value = pp.normalize_id(self.input_var.get())
        if not value:
            self.status_var.set("IDを入力してください")
            return "break"
        self.commit_id(value)
        return "break"

    def validate_id(self, value: str) -> tuple[bool, str]:
        if not pp.ID_PATTERN.fullmatch(value):
            return False, "IDは数字から始め、数字と英小文字を交互の階層にしてください（例: 1a2b）。"
        return True, ""

    def commit_id(self, folgezettel_id: str):
        if not self.folder or self.current_index >= len(self.items):
            return
        folgezettel_id = pp.normalize_id(folgezettel_id)
        valid, error = self.validate_id(folgezettel_id)
        if not valid:
            self.status_var.set(error)
            return
        if any(item.processed and item.folgezettel_id == folgezettel_id
               for item in self.items):
            self.status_var.set(f"ID「{folgezettel_id}」はすでに使用されています")
            return
        item = self.items[self.current_index]
        old_path = item.current_path(self.folder)
        new_path = self.folder / (folgezettel_id + old_path.suffix.lower())
        if new_path.exists() and new_path.resolve() != old_path.resolve():
            self.status_var.set(f"ファイル「{new_path.name}」はすでに存在します")
            return
        old_state = {
            "current_name": item.current_name,
            "folgezettel_id": item.folgezettel_id,
            "processed": item.processed,
        }
        try:
            old_path.rename(new_path)
        except OSError as exc:
            messagebox.showerror("名前を変更できません", f"{old_path.name}\n→ {new_path.name}\n\n{exc}")
            return
        item.current_name = new_path.name
        item.folgezettel_id = folgezettel_id
        item.processed = True
        self.undo_stack.append({
            "index": self.current_index,
            "old_name": old_state["current_name"],
            "new_name": new_path.name,
            "old_state": old_state,
        })
        self.current_index += 1
        self.hide_input()
        self.save_project()
        self.load_current_image()

    def undo_last(self):
        if not self.folder or not self.undo_stack:
            self.status_var.set("戻せる操作がありません")
            return
        record = self.undo_stack.pop()
        index = int(record["index"])
        item = self.items[index]
        current_path = self.folder / record["new_name"]
        restored_path = self.folder / record["old_name"]
        if restored_path.exists() and restored_path.resolve() != current_path.resolve():
            messagebox.showerror("取り消せません", f"元のファイル名「{restored_path.name}」がすでに存在します。")
            self.undo_stack.append(record)
            return
        try:
            current_path.rename(restored_path)
        except OSError as exc:
            messagebox.showerror("取り消せません", str(exc))
            self.undo_stack.append(record)
            return
        old_state = record.get("old_state") or {}
        item.current_name = old_state.get("current_name", record["old_name"])
        item.folgezettel_id = old_state.get("folgezettel_id")
        item.processed = bool(old_state.get("processed", False))
        self.current_index = index
        self.hide_input()
        self.save_project()
        self.load_current_image()
        self.status_var.set("直前の名前変更を取り消しました")

    def finish_work(self):
        self.save_project()
        self.image_canvas.delete("all")
        self.image_canvas.create_text(
            self.image_canvas.winfo_width() // 2,
            self.image_canvas.winfo_height() // 2,
            text="すべての画像にIDが付きました。移動して同期します…",
            fill="white", font=(self.ui_font, 18, "bold"), anchor="center",
        )
        self.naming_progress.configure(maximum=max(len(self.items), 1), value=len(self.items))
        self.progress_var.set(f"{len(self.items)} / {len(self.items)}")
        self.status_var.set("移動して同期しています…")
        self.root.after(100, lambda: self.move_processed(auto=True))

    # ---------- 移動＋同期 ----------
    def move_processed(self, auto: bool):
        if self.moving or not self.folder:
            return
        processed = [item for item in self.items if item.processed]
        if not processed:
            self.status_var.set("名前付け済みの画像がありません")
            return
        if not auto:
            if not messagebox.askyesno(
                "移動して同期",
                f"名前付け済みの{len(processed)}枚を次へ移動します。\n\n{self.dest}\n\n"
                "移動後に紙PKM Index と Folgezettel-Index を再生成して同期します。よろしいですか？",
            ):
                return
        self.moving = True
        try:
            assignments = [
                (item.current_path(self.folder), item.folgezettel_id or "")
                for item in processed
            ]
            moved, errors = pp.move_images(self.vault_root, self.dest, assignments)
            regen_ok = True
            try:
                regen_ok = pp.regen(self.vault_root)
            except Exception:
                regen_ok = False
                traceback.print_exc()

            moved_ids = {fid for fid, _p in moved}
            self.items = [item for item in self.items
                          if not (item.processed and item.folgezettel_id in moved_ids)]
            self.current_index = self.first_unprocessed_index()
            self.undo_stack.clear()
            if self.items:
                self.save_project()
            else:
                project = self.project_path()
                if project and project.exists():
                    try:
                        project.unlink()
                    except OSError:
                        pass

            message = f"{len(moved)}枚を {self.dest} へ移動しました。"
            if regen_ok:
                message += "\nIndex・グループ・Folgezettel-Index を再生成して同期しました。"
            else:
                message += "\n（Index の再生成に失敗しました。紙PKM Index を確認してください）"
            if errors:
                message += "\n\n移動できなかった画像:\n" + "\n".join(
                    f"{src.name}（{fid}）: {reason}" for src, fid, reason in errors
                )
            self.refresh_tree()
            if errors:
                messagebox.showwarning("一部移動できませんでした", message)
            else:
                messagebox.showinfo("移動しました", message)
            if self.items:
                self.show_setup()
                self.status_var.set(f"残り{len(self.items)}枚です")
            else:
                self.image_canvas.delete("all")
                self.image_canvas.create_text(
                    self.image_canvas.winfo_width() // 2,
                    self.image_canvas.winfo_height() // 2,
                    text="完了しました。ウィンドウを閉じてください。",
                    fill="white", font=(self.ui_font, 18, "bold"), anchor="center",
                )
                self.status_var.set("完了")
        finally:
            self.moving = False

    def on_close(self):
        if self.folder:
            self.save_project()
        self.root.destroy()


def _write_error_log(exc_type, exc_value, exc_traceback):
    details = "".join(traceback.format_exception(exc_type, exc_value, exc_traceback))
    try:
        (Path.home() / ".config" / "simple_yurii_note").mkdir(parents=True, exist_ok=True)
        (Path.home() / ".config" / "simple_yurii_note" / "folgezettel_scan_error.log").write_text(
            details, encoding="utf-8")
    except OSError:
        pass
    try:
        messagebox.showerror(
            "エラーが発生しました",
            "処理を続けられないエラーが発生しました。\n"
            "~/.config/simple_yurii_note/folgezettel_scan_error.log を確認してください。",
        )
    except Exception:
        pass


def main(argv: list[str]) -> int:
    import argparse

    ap = argparse.ArgumentParser(prog="folgezettel_scan.py")
    ap.add_argument("--root", required=True, help="vault ルート（同期の基準）")
    ap.add_argument("--dest", required=True, help="画像の移動先（今開いている Index のフォルダ）")
    args = ap.parse_args(argv)

    vault_root = Path(args.root).resolve()
    dest = Path(args.dest).resolve()
    if not vault_root.is_dir():
        print(f"folgezettel_scan: vault がありません: {vault_root}", file=sys.stderr)
        return 1
    if not dest.is_dir():
        print(f"folgezettel_scan: 移動先がありません: {dest}", file=sys.stderr)
        return 1

    sys.excepthook = _write_error_log
    root = tk.Tk()
    root.report_callback_exception = _write_error_log
    ScanApp(root, vault_root, dest)
    root.mainloop()
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
