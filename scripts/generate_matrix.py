import json

# Load the JSON files.
with open("official_image_metadata.json") as f:
    official_image_metadata = json.load(f)

with open("s6_architecture_mappings.json") as f:
    s6_architecture_mappings = json.load(f)

# Generate the matrix.
json_data = []
for image, versions in official_image_metadata.items():
    for version_info in versions:
        image_version = version_info["version"]
        for arch in version_info["architectures"]:
            architecture_data = s6_architecture_mappings[arch]
            platform = architecture_data["platform"]
            s6_architecture = architecture_data["s6_architecture"]
            json_data.append(
                {
                    "platform": platform,
                    "image": image,
                    "image_version": image_version,
                    "s6_architecture": s6_architecture,
                }
            )

matrix = {"include": json_data}

print(json.dumps(matrix, indent=4))

# Save the matrix to a file.
with open("matrix.json", "w") as f:
    json.dump(matrix, f)
