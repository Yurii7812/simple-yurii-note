import tempfile
import unittest
from pathlib import Path
from unittest import mock

import gallery


class GalleryPathTests(unittest.TestCase):
    def test_windows_drive_image_path_is_not_mistaken_for_url(self):
        note = Path("note.md").resolve()
        result = gallery.markdown_url_to_path(note, r"C:\Pictures\summer photo.jpg")

        self.assertIsNotNone(result)
        self.assertTrue(str(result).endswith(r"C:\Pictures\summer photo.jpg"))
        self.assertTrue(gallery.is_potential_local_image_url(r"D:\images\cat.PNG"))

    def test_remote_image_is_not_exposed_as_local_file(self):
        note = Path("note.md").resolve()

        self.assertIsNone(gallery.markdown_url_to_path(note, "https://example.com/cat.jpg"))


class GalleryPageTests(unittest.TestCase):
    def test_page_contains_search_controls_and_searchable_metadata(self):
        with tempfile.TemporaryDirectory() as directory:
            image = Path(directory) / "東京-cat.jpg"
            image.write_bytes(b"image")
            page = gallery.render_gallery_page(
                Path(directory) / "animals.md",
                [gallery.image_item(image, "猫", "公園で撮影", [{"label": "source", "href": "https://example.com"}])],
                None,
                mode="note",
            ).decode("utf-8")

        self.assertIn('id="search"', page)
        self.assertIn("function searchableText(item)", page)
        self.assertIn("東京-cat.jpg", page)
        self.assertIn("公園で撮影", page)


class BrowserTests(unittest.TestCase):
    def test_browser_falls_back_to_webbrowser(self):
        with mock.patch.object(gallery.os, "name", "posix"), mock.patch.object(
            gallery.webbrowser, "open", return_value=True
        ) as browser_open:
            self.assertTrue(gallery.open_browser("http://127.0.0.1:8765/gallery"))

        browser_open.assert_called_once()


if __name__ == "__main__":
    unittest.main()
