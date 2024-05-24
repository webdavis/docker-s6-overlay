import json
import argparse
from typing import Any, Dict, Optional


# Constants.
OFFICIAL_IMAGE_METADATA_FILE = "official_image_metadata.json"
S6_ARCHITECTURE_MAPPINGS_FILE = "s6_architecture_mappings.json"
OUTPUT_FILE = "matrix.json"


class JsonFileHandler:
    """Handles loading and saving JSON files."""

    @staticmethod
    def load(filename: str) -> Optional[Dict[str, Any]]:
        """Load JSON data from a file."""
        try:
            with open(filename) as f:
                return json.load(f)
        except FileNotFoundError:
            print(f"Error: {filename} not found.")
        except json.JSONDecodeError:
            print(f"Error: {filename} is not a valid JSON file.")
        return None

    @staticmethod
    def save(data: Dict[str, Any], filename: str, pretty: bool = False) -> None:
        """Save data to a JSON file."""
        try:
            with open(filename, "w") as f:
                json.dump(data, f, indent=4 if pretty else None)
        except IOError as e:
            print(f"Error saving JSON to {filename}: {e}")


class Matrix:
    """Utility functions that manipulate the GitHub Actions matrix."""

    @staticmethod
    def generate(
        official_image_metadata: Dict[str, Any],
        s6_architecture_mappings: Dict[str, Any],
    ) -> Dict[str, Any]:
        """Generate the matrix from the provided metadata."""
        matrix = []
        for image, versions in official_image_metadata.items():
            for version_info in versions:
                image_version = version_info["version"]
                for arch in version_info["architectures"]:
                    if arch in s6_architecture_mappings:
                        architecture_data = s6_architecture_mappings[arch]
                        platform = architecture_data["platform"]
                        s6_architecture = architecture_data["s6_architecture"]
                        matrix.append(
                            {
                                "platform": platform,
                                "image": image,
                                "image_version": image_version,
                                "s6_architecture": s6_architecture,
                            }
                        )
                    else:
                        print(
                            f"Warning: Architecture {arch} not found in s6_architecture_mappings."
                        )

        return {"include": matrix}

    @staticmethod
    def print(data: Dict[str, Any], pretty: bool = False) -> None:
        """Pretty prints the JSON to STDOUT."""
        if pretty:
            print(json.dumps(data, indent=4))
        else:
            print(json.dumps(data))


def parse_command_flags() -> argparse.Namespace:
    """Parse all command line flags for this script."""
    parser = argparse.ArgumentParser(
        description="Creates a GitHub Actions matrix in the form of JSON."
    )

    parser.add_argument(
        "-p",
        "--print",
        action="count",
        default=0,
        help="Print the JSON to STDOUT. Optionally pretty print if 'pretty' is specified.",
    )

    return parser.parse_args()


def main() -> None:
    args = parse_command_flags()

    official_image_metadata = JsonFileHandler.load(OFFICIAL_IMAGE_METADATA_FILE)
    s6_architecture_mappings = JsonFileHandler.load(S6_ARCHITECTURE_MAPPINGS_FILE)

    if official_image_metadata is None or s6_architecture_mappings is None:
        print("Error: Failed to load necessary JSON files.")
        return

    matrix = Matrix.generate(official_image_metadata, s6_architecture_mappings)

    if args.print:
        Matrix.print(matrix, pretty=(args.print >= 2))
    else:
        JsonFileHandler.save(matrix, OUTPUT_FILE, pretty=True)


if __name__ == "__main__":
    main()
