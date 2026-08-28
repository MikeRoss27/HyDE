#!/usr/bin/env python3
"""HyDE Files — a focused GTK4 file manager for everyday navigation."""

from __future__ import annotations

import mimetypes
import os
import shutil
from pathlib import Path
from urllib.parse import quote

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Gdk", "4.0")
gi.require_version("Gio", "2.0")
from gi.repository import Gdk, Gio, GLib, Gtk, Pango  # noqa: E402


APP_ID = "io.hyde.Files"


class HyDEFiles(Gtk.Application):
    def __init__(self) -> None:
        super().__init__(application_id=APP_ID)
        self.current_path = Path.home()
        self.history: list[Path] = []
        self.history_index = -1
        self.selected_path: Path | None = None
        self.clipboard_paths: list[Path] = []
        self.grid_view = True
        self.show_hidden = False
        self.volume_monitor = Gio.VolumeMonitor.get()
        self.connect("activate", self.on_activate)

    def on_activate(self, *_args: object) -> None:
        self.install_css()
        self.window = Gtk.ApplicationWindow(application=self, title="Fichiers")
        self.window.set_default_size(1280, 780)
        self.window.set_size_request(900, 580)
        self.window.connect("close-request", lambda *_: False)
        self.build_ui()
        self.volume_monitor.connect("mount-added", lambda *_: self.refresh_volumes())
        self.volume_monitor.connect("mount-removed", lambda *_: self.refresh_volumes())
        self.volume_monitor.connect("volume-added", lambda *_: self.refresh_volumes())
        self.volume_monitor.connect("volume-removed", lambda *_: self.refresh_volumes())
        self.navigate(self.current_path, push_history=True)
        self.window.present()

    def install_css(self) -> None:
        css = b"""
        window { background: #10151f; color: #e7edf7; font-family: Cantarell, sans-serif; }
        .shell { background: linear-gradient(135deg, #10151f, #151729); }
        .topbar { padding: 12px 16px; border-bottom: 1px solid rgba(196, 204, 255, .10); }
        .toolbar-button, .crumb, .side-row, .action-button { border-radius: 12px; min-height: 34px; }
        button { color: #dbe5f6; background: transparent; border: 1px solid transparent; box-shadow: none; }
        button:hover { background: rgba(142, 164, 255, .12); border-color: rgba(180, 191, 255, .12); }
        button:active { background: rgba(125, 230, 218, .20); }
        .primary { background: rgba(91, 207, 195, .20); color: #bffcf4; border-color: rgba(115, 237, 220, .30); }
        .primary:hover { background: rgba(91, 207, 195, .32); }
        .path-entry { min-height: 38px; border-radius: 12px; background: rgba(255,255,255,.055); border: 1px solid rgba(196,204,255,.10); padding: 0 10px; }
        .search { min-height: 38px; border-radius: 12px; background: rgba(255,255,255,.055); border: 1px solid rgba(196,204,255,.10); padding: 0 10px; }
        .sidebar { background: rgba(8, 12, 19, .36); border-right: 1px solid rgba(196,204,255,.09); padding: 12px; }
        .sidebar-title { color: #9ba8c3; font-size: 11px; font-weight: 700; margin: 14px 10px 5px; }
        .side-row { padding: 7px 10px; margin: 1px 0; }
        .side-row:selected, .side-row.active { background: rgba(124, 102, 236, .22); color: #eeeaff; border: 1px solid rgba(170, 154, 255, .26); }
        .content { padding: 18px 22px; }
        .section-title { font-size: 15px; font-weight: 700; color: #edf3ff; }
        flowboxchild { border-radius: 14px; margin: 5px; }
        flowboxchild:hover { background: rgba(255,255,255,.055); }
        flowboxchild:selected { background: rgba(100, 218, 207, .16); outline: 1px solid rgba(126, 238, 224, .45); }
        .file-tile { min-width: 138px; min-height: 136px; padding: 12px; border-radius: 14px; }
        .file-name { color: #e8edf6; font-weight: 600; }
        .file-meta { color: #91a0b9; font-size: 11px; }
        .preview { background: rgba(8,12,19,.42); border-left: 1px solid rgba(196,204,255,.09); padding: 16px; }
        .preview-title { font-size: 16px; font-weight: 700; color: #eef3ff; }
        .preview-meta { color: #9aa8bf; font-size: 12px; }
        .preview-image { border-radius: 12px; background: #0c111b; }
        .status { padding: 8px 16px; color: #8f9eb7; font-size: 12px; border-top: 1px solid rgba(196,204,255,.08); }
        .empty { color: #9ba8c3; font-size: 15px; }
        """
        provider = Gtk.CssProvider()
        provider.load_from_data(css)
        Gtk.StyleContext.add_provider_for_display(
            Gdk.Display.get_default(), provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        )

    def icon_button(self, icon: str, tooltip: str, callback, css_class: str = "toolbar-button") -> Gtk.Button:
        button = Gtk.Button.new_from_icon_name(icon)
        button.set_tooltip_text(tooltip)
        button.add_css_class(css_class)
        button.connect("clicked", callback)
        return button

    def build_ui(self) -> None:
        root = Gtk.Box.new(Gtk.Orientation.VERTICAL, 0)
        root.add_css_class("shell")
        self.window.set_child(root)

        topbar = Gtk.Box.new(Gtk.Orientation.HORIZONTAL, 8)
        topbar.add_css_class("topbar")
        root.append(topbar)
        topbar.append(self.icon_button("go-previous-symbolic", "Précédent", self.go_back))
        topbar.append(self.icon_button("go-next-symbolic", "Suivant", self.go_forward))
        topbar.append(self.icon_button("go-up-symbolic", "Dossier parent", lambda *_: self.navigate(self.current_path.parent)))

        self.path_entry = Gtk.Entry()
        self.path_entry.add_css_class("path-entry")
        self.path_entry.set_hexpand(True)
        self.path_entry.set_icon_from_icon_name(Gtk.EntryIconPosition.PRIMARY, "folder-symbolic")
        self.path_entry.connect("activate", self.path_entered)
        topbar.append(self.path_entry)

        self.search = Gtk.SearchEntry()
        self.search.add_css_class("search")
        self.search.set_placeholder_text("Rechercher dans ce dossier")
        self.search.set_width_chars(25)
        self.search.connect("search-changed", lambda *_: self.populate_files())
        topbar.append(self.search)
        topbar.append(self.icon_button("view-grid-symbolic", "Affichage en tuiles", self.use_grid, "primary"))
        topbar.append(self.icon_button("view-list-symbolic", "Affichage en liste", self.use_list))

        body = Gtk.Paned.new(Gtk.Orientation.HORIZONTAL)
        body.set_wide_handle(False)
        root.append(body)

        self.sidebar = self.build_sidebar()
        body.set_start_child(self.sidebar)
        body.set_resize_start_child(False)
        body.set_shrink_start_child(False)

        centre = Gtk.Box.new(Gtk.Orientation.VERTICAL, 10)
        centre.add_css_class("content")
        body.set_resize_end_child(False)
        body.set_position(222)
        body.set_resize_start_child(False)

        self.build_preview()
        middle = Gtk.Paned.new(Gtk.Orientation.HORIZONTAL)
        middle.set_start_child(centre)
        middle.set_end_child(self.preview)
        middle.set_position(880)
        middle.set_resize_end_child(False)
        body.set_end_child(middle)

        commands = Gtk.Box.new(Gtk.Orientation.HORIZONTAL, 6)
        new_folder = Gtk.Button.new_from_icon_name("folder-new-symbolic")
        new_folder.set_label("Nouveau dossier")
        new_folder.add_css_class("primary")
        new_folder.connect("clicked", self.new_folder)
        commands.append(new_folder)
        commands.append(self.icon_button("edit-copy-symbolic", "Copier la sélection", self.copy_selected))
        commands.append(self.icon_button("edit-paste-symbolic", "Coller ici", self.paste_files))
        commands.append(self.icon_button("user-trash-symbolic", "Mettre à la corbeille", self.trash_selected))
        commands.append(self.icon_button("view-refresh-symbolic", "Actualiser", lambda *_: self.populate_files()))
        centre.append(commands)

        self.folder_label = Gtk.Label(xalign=0)
        self.folder_label.add_css_class("section-title")
        centre.append(self.folder_label)
        self.scroller = Gtk.ScrolledWindow()
        self.scroller.set_vexpand(True)
        centre.append(self.scroller)

        self.status = Gtk.Label(xalign=0)
        self.status.add_css_class("status")
        root.append(self.status)

        key_controller = Gtk.EventControllerKey.new()
        key_controller.connect("key-pressed", self.on_key_pressed)
        self.window.add_controller(key_controller)

    def build_sidebar(self) -> Gtk.Widget:
        column = Gtk.Box.new(Gtk.Orientation.VERTICAL, 0)
        column.set_size_request(222, -1)
        column.add_css_class("sidebar")
        self.sidebar_rows: list[tuple[Gtk.Button, Path]] = []

        title = Gtk.Label(label="ACCÈS RAPIDE", xalign=0)
        title.add_css_class("sidebar-title")
        column.append(title)
        home = Path.home()
        places = [
            ("user-home-symbolic", "Accueil", home),
            ("user-desktop-symbolic", "Bureau", home / "Desktop"),
            ("folder-documents-symbolic", "Documents", home / "Documents"),
            ("folder-download-symbolic", "Téléchargements", home / "Downloads"),
            ("folder-pictures-symbolic", "Images", home / "Pictures"),
            ("folder-music-symbolic", "Musique", home / "Music"),
            ("folder-videos-symbolic", "Vidéos", home / "Videos"),
            ("user-trash-symbolic", "Corbeille", home / ".local/share/Trash/files"),
        ]
        for icon, label, place in places:
            button = Gtk.Button()
            button.add_css_class("side-row")
            row = Gtk.Box.new(Gtk.Orientation.HORIZONTAL, 10)
            row.append(Gtk.Image.new_from_icon_name(icon))
            row.append(Gtk.Label(label=label, xalign=0, hexpand=True))
            button.set_child(row)
            button.connect("clicked", lambda _button, location=place: self.navigate(location))
            column.append(button)
            self.sidebar_rows.append((button, place))

        storage = Gtk.Label(label="EMPLACEMENTS", xalign=0)
        storage.add_css_class("sidebar-title")
        column.append(storage)
        root_button = Gtk.Button()
        root_button.add_css_class("side-row")
        root_row = Gtk.Box.new(Gtk.Orientation.HORIZONTAL, 10)
        root_row.append(Gtk.Image.new_from_icon_name("drive-harddisk-symbolic"))
        root_row.append(Gtk.Label(label="Système de fichiers", xalign=0))
        root_button.set_child(root_row)
        root_button.connect("clicked", lambda *_: self.navigate(Path("/")))
        column.append(root_button)
        self.sidebar_rows.append((root_button, Path("/")))

        devices = Gtk.Label(label="PÉRIPHÉRIQUES", xalign=0)
        devices.add_css_class("sidebar-title")
        column.append(devices)
        self.devices_box = Gtk.Box.new(Gtk.Orientation.VERTICAL, 2)
        column.append(self.devices_box)
        self.refresh_volumes()
        return column

    def refresh_volumes(self) -> None:
        """Show removable and external volumes, mounted or not, in the sidebar."""
        while child := self.devices_box.get_first_child():
            self.devices_box.remove(child)
        seen: set[str] = set()
        for volume in self.volume_monitor.get_volumes():
            identifier = volume.get_identifier(Gio.VOLUME_IDENTIFIER_KIND_UUID) or volume.get_name()
            if identifier in seen:
                continue
            seen.add(identifier)
            mount = volume.get_mount()
            row = Gtk.Box.new(Gtk.Orientation.HORIZONTAL, 4)
            row.add_css_class("side-row")
            open_button = Gtk.Button()
            open_button.set_hexpand(True)
            open_content = Gtk.Box.new(Gtk.Orientation.HORIZONTAL, 8)
            open_content.append(Gtk.Image.new_from_gicon(volume.get_icon()))
            label = volume.get_name() + ("" if mount else " · Monter")
            open_content.append(Gtk.Label(label=label, xalign=0, ellipsize=Pango.EllipsizeMode.END, hexpand=True))
            open_button.set_child(open_content)
            if mount:
                root = mount.get_root()
                open_button.connect("clicked", lambda _button, location=root: self.navigate(Path(location.get_path())))
            else:
                open_button.connect("clicked", lambda _button, target=volume: self.mount_volume(target))
            row.append(open_button)
            if mount and mount.can_eject():
                eject = self.icon_button("media-eject-symbolic", "Éjecter en toute sécurité", lambda _button, target=mount: self.eject_mount(target))
                row.append(eject)
            self.devices_box.append(row)

        if not seen:
            empty = Gtk.Label(label="Aucun périphérique externe", xalign=0)
            empty.add_css_class("file-meta")
            empty.set_margin_start(10)
            self.devices_box.append(empty)

    def mount_volume(self, volume: Gio.Volume) -> None:
        volume.mount(Gio.MountMountFlags.NONE, None, None, self.mount_finished, volume)

    def mount_finished(self, volume: Gio.Volume, result: Gio.AsyncResult, _data: object) -> None:
        try:
            volume.mount_finish(result)
            mount = volume.get_mount()
            if mount:
                self.navigate(Path(mount.get_root().get_path()))
        except GLib.Error as error:
            self.show_error("Montage impossible", error.message)
        self.refresh_volumes()

    def eject_mount(self, mount: Gio.Mount) -> None:
        mount.eject_with_operation(Gio.MountUnmountFlags.NONE, None, None, self.eject_finished, mount)

    def eject_finished(self, mount: Gio.Mount, result: Gio.AsyncResult, _data: object) -> None:
        try:
            mount.eject_with_operation_finish(result)
        except GLib.Error as error:
            self.show_error("Éjection impossible", error.message)
        self.refresh_volumes()

    def build_preview(self) -> Gtk.Widget:
        self.preview = Gtk.Box.new(Gtk.Orientation.VERTICAL, 12)
        self.preview.set_size_request(270, -1)
        self.preview.add_css_class("preview")
        self.preview_media = Gtk.Stack()
        self.preview_media.set_size_request(230, 170)
        self.preview_media.set_halign(Gtk.Align.FILL)
        self.preview_icon = Gtk.Image.new_from_icon_name("folder-symbolic")
        self.preview_icon.set_pixel_size(72)
        self.preview_picture = Gtk.Picture()
        self.preview_picture.set_can_shrink(True)
        self.preview_picture.set_content_fit(Gtk.ContentFit.CONTAIN)
        self.preview_media.add_named(self.preview_icon, "icon")
        self.preview_media.add_named(self.preview_picture, "picture")
        self.preview_media.set_visible_child_name("icon")
        self.preview.append(self.preview_media)
        self.preview_title = Gtk.Label(label="Aucune sélection", xalign=0, wrap=True)
        self.preview_title.add_css_class("preview-title")
        self.preview.append(self.preview_title)
        self.preview_meta = Gtk.Label(label="Sélectionne un fichier pour afficher ses détails.", xalign=0, wrap=True)
        self.preview_meta.add_css_class("preview-meta")
        self.preview.append(self.preview_meta)
        self.open_button = Gtk.Button(label="Ouvrir")
        self.open_button.add_css_class("primary")
        self.open_button.connect("clicked", lambda *_: self.open_selected())
        self.preview.append(self.open_button)
        return self.preview

    def navigate(self, location: Path, push_history: bool = True) -> None:
        location = location.expanduser()
        if not location.exists() or not location.is_dir():
            self.show_error("Emplacement indisponible", str(location))
            return
        self.current_path = location.resolve()
        if push_history:
            self.history = self.history[: self.history_index + 1]
            self.history.append(self.current_path)
            self.history_index += 1
        self.path_entry.set_text(str(self.current_path))
        self.search.set_text("")
        self.selected_path = None
        self.update_sidebar()
        self.populate_files()
        self.clear_preview()

    def path_entered(self, entry: Gtk.Entry) -> None:
        self.navigate(Path(entry.get_text()))

    def go_back(self, *_args: object) -> None:
        if self.history_index > 0:
            self.history_index -= 1
            self.navigate(self.history[self.history_index], push_history=False)

    def go_forward(self, *_args: object) -> None:
        if self.history_index + 1 < len(self.history):
            self.history_index += 1
            self.navigate(self.history[self.history_index], push_history=False)

    def update_sidebar(self) -> None:
        for button, location in self.sidebar_rows:
            if location == self.current_path:
                button.add_css_class("active")
            else:
                button.remove_css_class("active")

    def sorted_entries(self) -> list[Path]:
        query = self.search.get_text().casefold().strip()
        try:
            entries = list(self.current_path.iterdir())
        except PermissionError:
            self.show_error("Accès refusé", str(self.current_path))
            return []
        if not self.show_hidden:
            entries = [item for item in entries if not item.name.startswith(".")]
        if query:
            entries = [item for item in entries if query in item.name.casefold()]
        return sorted(entries, key=lambda item: (not item.is_dir(), item.name.casefold()))

    def populate_files(self) -> None:
        if self.grid_view:
            self.populate_grid()
        else:
            self.populate_list()

    def reset_content(self, content: Gtk.Widget) -> None:
        self.scroller.set_child(content)
        self.folder_label.set_text(self.current_path.name or "Système de fichiers")

    def populate_grid(self) -> None:
        grid = Gtk.FlowBox()
        grid.set_selection_mode(Gtk.SelectionMode.SINGLE)
        grid.set_max_children_per_line(6)
        grid.set_min_children_per_line(3)
        grid.set_row_spacing(8)
        grid.set_column_spacing(8)
        grid.set_activate_on_single_click(False)
        grid.set_valign(Gtk.Align.START)
        grid.set_vexpand(False)
        grid.connect("child-activated", self.activate_child)
        grid.connect("selected-children-changed", self.grid_selection_changed)
        entries = self.sorted_entries()
        for item in entries:
            tile = Gtk.Box.new(Gtk.Orientation.VERTICAL, 6)
            tile.add_css_class("file-tile")
            tile.set_size_request(150, 140)
            image = self.image_for(item, 48)
            image.set_halign(Gtk.Align.CENTER)
            tile.append(image)
            name = Gtk.Label(label=item.name, wrap=True, justify=Gtk.Justification.CENTER, max_width_chars=18)
            name.add_css_class("file-name")
            name.set_ellipsize(Pango.EllipsizeMode.END)
            tile.append(name)
            meta = Gtk.Label(label=self.file_meta(item), justify=Gtk.Justification.CENTER)
            meta.add_css_class("file-meta")
            tile.append(meta)
            child = Gtk.FlowBoxChild()
            child.set_valign(Gtk.Align.START)
            child.set_child(tile)
            child.file_path = item
            grid.append(child)
        if not entries:
            grid.append(Gtk.Label(label="Ce dossier est vide", css_classes=["empty"]))
        self.reset_content(grid)
        self.status.set_text(f"{len(entries)} élément(s) · {self.current_path}")

    def populate_list(self) -> None:
        rows = Gtk.ListBox()
        rows.set_selection_mode(Gtk.SelectionMode.SINGLE)
        rows.connect("row-activated", self.activate_row)
        rows.connect("selected-rows-changed", self.list_selection_changed)
        entries = self.sorted_entries()
        for item in entries:
            row = Gtk.ListBoxRow()
            row.file_path = item
            content = Gtk.Box.new(Gtk.Orientation.HORIZONTAL, 12)
            content.set_margin_top(7)
            content.set_margin_bottom(7)
            content.set_margin_start(8)
            content.set_margin_end(8)
            content.append(self.image_for(item, 26))
            label = Gtk.Label(label=item.name, xalign=0, hexpand=True)
            label.add_css_class("file-name")
            label.set_ellipsize(Pango.EllipsizeMode.END)
            content.append(label)
            info = Gtk.Label(label=self.file_meta(item), xalign=1)
            info.add_css_class("file-meta")
            content.append(info)
            row.set_child(content)
            rows.append(row)
        self.reset_content(rows)
        self.status.set_text(f"{len(entries)} élément(s) · {self.current_path}")

    def image_for(self, item: Path, size: int) -> Gtk.Image:
        if item.is_dir():
            image = Gtk.Image.new_from_icon_name("folder-symbolic")
        else:
            guessed, _encoding = mimetypes.guess_type(item.name)
            image = (
                Gtk.Image.new_from_gicon(Gio.content_type_get_icon(guessed))
                if guessed
                else Gtk.Image.new_from_icon_name("text-x-generic-symbolic")
            )
        image.set_pixel_size(size)
        return image

    def file_meta(self, item: Path) -> str:
        if item.is_dir():
            try:
                return f"{sum(1 for _ in item.iterdir())} éléments"
            except PermissionError:
                return "Dossier"
        try:
            size = item.stat().st_size
        except OSError:
            return "Fichier"
        for unit in ("o", "Ko", "Mo", "Go"):
            if size < 1024 or unit == "Go":
                return f"{size:.0f} {unit}" if unit == "o" else f"{size:.1f} {unit}"
            size /= 1024
        return "Fichier"

    def grid_selection_changed(self, grid: Gtk.FlowBox) -> None:
        chosen = grid.get_selected_children()
        self.select_path(chosen[0].file_path if chosen else None)

    def list_selection_changed(self, rows: Gtk.ListBox) -> None:
        chosen = rows.get_selected_row()
        self.select_path(chosen.file_path if chosen else None)

    def activate_child(self, _grid: Gtk.FlowBox, child: Gtk.FlowBoxChild) -> None:
        self.activate_path(child.file_path)

    def activate_row(self, _rows: Gtk.ListBox, row: Gtk.ListBoxRow) -> None:
        self.activate_path(row.file_path)

    def activate_path(self, item: Path) -> None:
        if item.is_dir():
            self.navigate(item)
        else:
            self.select_path(item)
            self.open_selected()

    def select_path(self, item: Path | None) -> None:
        self.selected_path = item
        if item is None:
            self.clear_preview()
            return
        self.preview_title.set_text(item.name)
        kind = "Dossier" if item.is_dir() else (mimetypes.guess_type(item.name)[0] or "Fichier")
        try:
            modified = GLib.DateTime.new_from_unix_local(item.stat().st_mtime).format("%d/%m/%Y à %H:%M")
        except OSError:
            modified = "inconnu"
        self.preview_meta.set_text(f"{kind}\n{self.file_meta(item)}\nModifié le {modified}\n{item}")
        self.preview_icon.set_from_icon_name("folder-symbolic" if item.is_dir() else "text-x-generic-symbolic")
        self.preview_media.set_visible_child_name("icon")
        if item.is_file() and mimetypes.guess_type(item.name)[0] and mimetypes.guess_type(item.name)[0].startswith("image/"):
            try:
                texture = Gdk.Texture.new_from_file(Gio.File.new_for_path(str(item)))
                self.preview_picture.set_paintable(texture)
                self.preview_media.set_visible_child_name("picture")
            except GLib.Error:
                pass

    def clear_preview(self) -> None:
        self.preview_icon.set_from_icon_name("folder-symbolic")
        self.preview_icon.set_pixel_size(72)
        self.preview_picture.set_paintable(None)
        self.preview_media.set_visible_child_name("icon")
        self.preview_title.set_text("Aucune sélection")
        self.preview_meta.set_text("Sélectionne un fichier pour afficher ses détails.")

    def open_selected(self) -> None:
        if not self.selected_path:
            return
        if self.selected_path.is_dir():
            self.navigate(self.selected_path)
            return
        uri = "file://" + quote(str(self.selected_path))
        try:
            Gio.AppInfo.launch_default_for_uri(uri, None)
        except GLib.Error as error:
            self.show_error("Impossible d’ouvrir ce fichier", error.message)

    def new_folder(self, *_args: object) -> None:
        base = self.current_path / "Nouveau dossier"
        candidate = base
        number = 2
        while candidate.exists():
            candidate = self.current_path / f"Nouveau dossier {number}"
            number += 1
        try:
            candidate.mkdir()
            self.populate_files()
            self.status.set_text(f"Dossier créé : {candidate.name}")
        except OSError as error:
            self.show_error("Création impossible", str(error))

    def copy_selected(self, *_args: object) -> None:
        if self.selected_path:
            self.clipboard_paths = [self.selected_path]
            self.status.set_text(f"Copié : {self.selected_path.name}")

    def paste_files(self, *_args: object) -> None:
        if not self.clipboard_paths:
            self.status.set_text("Aucun fichier à coller")
            return
        for source in self.clipboard_paths:
            target = self.current_path / source.name
            suffix = 2
            while target.exists():
                target = self.current_path / f"{source.stem} ({suffix}){source.suffix}"
                suffix += 1
            try:
                if source.is_dir():
                    shutil.copytree(source, target)
                else:
                    shutil.copy2(source, target)
            except OSError as error:
                self.show_error("Copie impossible", str(error))
                return
        self.populate_files()

    def trash_selected(self, *_args: object) -> None:
        if not self.selected_path:
            return
        try:
            Gio.File.new_for_path(str(self.selected_path)).trash(None)
            self.status.set_text(f"Déplacé dans la corbeille : {self.selected_path.name}")
            self.selected_path = None
            self.populate_files()
            self.clear_preview()
        except GLib.Error as error:
            self.show_error("Mise à la corbeille impossible", error.message)

    def use_grid(self, *_args: object) -> None:
        self.grid_view = True
        self.populate_files()

    def use_list(self, *_args: object) -> None:
        self.grid_view = False
        self.populate_files()

    def on_key_pressed(self, _controller, keyval, _keycode, state) -> bool:
        control = bool(state & Gdk.ModifierType.CONTROL_MASK)
        if control and keyval in (Gdk.KEY_l, Gdk.KEY_L):
            self.path_entry.grab_focus()
            self.path_entry.select_region(0, -1)
            return True
        if control and keyval in (Gdk.KEY_f, Gdk.KEY_F):
            self.search.grab_focus()
            return True
        if control and keyval in (Gdk.KEY_c, Gdk.KEY_C):
            self.copy_selected()
            return True
        if control and keyval in (Gdk.KEY_v, Gdk.KEY_V):
            self.paste_files()
            return True
        if keyval == Gdk.KEY_Delete:
            self.trash_selected()
            return True
        if control and keyval in (Gdk.KEY_h, Gdk.KEY_H):
            self.show_hidden = not self.show_hidden
            self.populate_files()
            self.status.set_text("Fichiers cachés affichés" if self.show_hidden else "Fichiers cachés masqués")
            return True
        return False

    def show_error(self, title: str, body: str) -> None:
        dialog = Gtk.AlertDialog.new(title, body)
        dialog.show(self.window)


if __name__ == "__main__":
    HyDEFiles().run(None)
