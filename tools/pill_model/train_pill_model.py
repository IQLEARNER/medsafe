"""Train a pill image classifier and export TensorFlow Lite assets.

Expected dataset layout:

  data/
    class_a/
      image1.jpg
      image2.jpg
    class_b/
      image3.jpg
      ...

The folder names become the labels used by the app. After training, this script
exports:

  artifacts/pill_classifier_saved_model/
  artifacts/pill_classifier.tflite
  artifacts/pill_labels.txt
"""

from __future__ import annotations

import argparse
import shutil
import tempfile
from pathlib import Path

from PIL import Image, ImageOps, UnidentifiedImageError
import tensorflow as tf


IMAGE_SIZE = 224
BATCH_SIZE = 32
EPOCHS = 15
SEED = 42


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Train a pill classifier")
    parser.add_argument(
        "--data-dir",
        type=Path,
        required=True,
        help="Directory containing pill images, either in class subfolders or flat with one image per file.",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path("artifacts"),
        help="Directory for SavedModel, .tflite, and labels output.",
    )
    return parser.parse_args()


def _is_image_file(path: Path) -> bool:
    return path.suffix.lower() in {".jpg", ".jpeg", ".png", ".bmp", ".gif", ".webp", ".avif"}


def _copy_as_png(source: Path, destination: Path) -> None:
    try:
        with Image.open(source) as image:
            normalized = ImageOps.exif_transpose(image).convert("RGB")
            destination.parent.mkdir(parents=True, exist_ok=True)
            normalized.save(destination, format="PNG")
    except UnidentifiedImageError as error:
        raise SystemExit(f"Unsupported image file: {source}") from error


def _prepare_dataset_root(data_dir: Path) -> tuple[Path, tempfile.TemporaryDirectory[str] | None]:
    has_class_dirs = any(child.is_dir() for child in data_dir.iterdir())
    temp_dir = tempfile.TemporaryDirectory(prefix="pill_model_dataset_")
    temp_root = Path(temp_dir.name)

    if has_class_dirs:
        image_count = 0
        for class_dir in sorted(child for child in data_dir.iterdir() if child.is_dir()):
            for image_file in sorted(class_dir.iterdir()):
                if not image_file.is_file() or not _is_image_file(image_file):
                    continue
                image_count += 1
                _copy_as_png(image_file, temp_root / class_dir.name / f"{image_file.stem}.png")

        if image_count == 0:
            temp_dir.cleanup()
            raise SystemExit(
                f"No images found in class folders under {data_dir}. Put images directly in the folder or inside class subfolders.",
            )

        return temp_root, temp_dir

    image_files = [child for child in data_dir.iterdir() if child.is_file() and _is_image_file(child)]
    if not image_files:
        temp_dir.cleanup()
        raise SystemExit(
            f"No images found in {data_dir}. Put images directly in the folder or inside class subfolders.",
        )

    for image_file in image_files:
        class_name = image_file.stem.strip()
        if not class_name:
            temp_dir.cleanup()
            raise SystemExit(f"Image file has an empty stem: {image_file.name}")

        _copy_as_png(image_file, temp_root / class_name / f"{class_name}.png")

    return temp_root, temp_dir


def build_datasets(data_dir: Path):
    train_ds = tf.keras.utils.image_dataset_from_directory(
        data_dir,
        validation_split=0.2,
        subset="training",
        seed=SEED,
        image_size=(IMAGE_SIZE, IMAGE_SIZE),
        batch_size=BATCH_SIZE,
    )

    val_ds = tf.keras.utils.image_dataset_from_directory(
        data_dir,
        validation_split=0.2,
        subset="validation",
        seed=SEED,
        image_size=(IMAGE_SIZE, IMAGE_SIZE),
        batch_size=BATCH_SIZE,
    )

    class_names = train_ds.class_names

    normalization = tf.keras.layers.Rescaling(1.0 / 255.0)
    autotune = tf.data.AUTOTUNE

    train_ds = train_ds.shuffle(1000).prefetch(buffer_size=autotune)
    val_ds = val_ds.prefetch(buffer_size=autotune)

    return train_ds, val_ds, class_names, normalization


def build_model(num_classes: int, normalization: tf.keras.layers.Layer) -> tf.keras.Model:
    base_model = tf.keras.applications.MobileNetV2(
        input_shape=(IMAGE_SIZE, IMAGE_SIZE, 3),
        include_top=False,
        weights="imagenet",
    )
    base_model.trainable = False

    inputs = tf.keras.Input(shape=(IMAGE_SIZE, IMAGE_SIZE, 3))
    x = normalization(inputs)
    x = base_model(x, training=False)
    x = tf.keras.layers.GlobalAveragePooling2D()(x)
    x = tf.keras.layers.Dropout(0.2)(x)
    outputs = tf.keras.layers.Dense(num_classes, activation="softmax")(x)

    model = tf.keras.Model(inputs, outputs)
    model.compile(
        optimizer=tf.keras.optimizers.Adam(learning_rate=1e-3),
        loss="sparse_categorical_crossentropy",
        metrics=["accuracy"],
    )
    return model


def export_labels(output_dir: Path, labels: list[str]) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    labels_path = output_dir / "pill_labels.txt"
    labels_path.write_text("\n".join(labels) + "\n", encoding="utf-8")


def export_tflite(output_dir: Path, model: tf.keras.Model) -> Path:
    saved_model_dir = output_dir / "pill_classifier_saved_model"
    model.export(saved_model_dir)

    converter = tf.lite.TFLiteConverter.from_saved_model(str(saved_model_dir))
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    tflite_model = converter.convert()

    tflite_path = output_dir / "pill_classifier.tflite"
    tflite_path.write_bytes(tflite_model)
    return tflite_path


def main() -> None:
    args = parse_args()
    data_dir = args.data_dir.expanduser().resolve()
    output_dir = args.output_dir.expanduser().resolve()

    if not data_dir.exists():
        raise SystemExit(f"Data directory does not exist: {data_dir}")

    dataset_root, temp_dataset = _prepare_dataset_root(data_dir)
    try:
        train_ds, val_ds, labels, normalization = build_datasets(dataset_root)
        model = build_model(len(labels), normalization)

        callbacks = [
            tf.keras.callbacks.EarlyStopping(
                monitor="val_accuracy",
                patience=3,
                restore_best_weights=True,
            )
        ]

        model.fit(train_ds, validation_data=val_ds, epochs=EPOCHS, callbacks=callbacks, shuffle=False)

        output_dir.mkdir(parents=True, exist_ok=True)
        export_labels(output_dir, labels)
        export_tflite(output_dir, model)

        print(f"Exported labels to {output_dir / 'pill_labels.txt'}")
        print(f"Exported model to {output_dir / 'pill_classifier.tflite'}")
    finally:
        if temp_dataset is not None:
            temp_dataset.cleanup()


if __name__ == "__main__":
    main()
