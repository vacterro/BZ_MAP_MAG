// Compile against the local VRV checkout's src/shared directory.
#include "TerrainFile.h"
#include <chrono>
#include <cmath>
#include <fstream>
#include <iostream>
#include <iterator>
#include <string>

static bool read(const char* path, vrv::terrain::Grid& grid) {
    std::ifstream input(path, std::ios::binary);
    const std::string bytes{std::istreambuf_iterator<char>(input), {}};
    return input.is_open() && vrv::terrain::Read(bytes, grid);
}

static int verify_graph(const vrv::terrain::Grid& base, const vrv::terrain::Grid& edited) {
    constexpr int focus = 520;
    const auto center = base.At(focus, focus);
    const auto block = base.Block(focus / 16, focus / 16);
    if (center >= base.Count() || block >= base.textures.size()) return 1;

    size_t heights = 0, colors = 0, tiles = 0;
    for (size_t i = 0; i < base.Count(); ++i) {
        const bool height_changed = base.height[i] != edited.height[i];
        const bool color_changed = base.colour[i * 3] != edited.colour[i * 3] ||
            base.colour[i * 3 + 1] != edited.colour[i * 3 + 1] ||
            base.colour[i * 3 + 2] != edited.colour[i * 3 + 2];
        const auto dx = static_cast<int>(i % base.width) - focus;
        const auto dz = static_cast<int>(i / base.width) - focus;
        if ((height_changed || color_changed) && dx * dx + dz * dz >= 64 * 64) return 1;
        heights += height_changed;
        colors += color_changed;
    }
    for (size_t i = 0; i < base.textures.size(); ++i) {
        if ((base.textures[i] & 0xfff0) != (edited.textures[i] & 0xfff0)) return 1;
        tiles += base.textures[i] != edited.textures[i];
    }
    std::cout << "Graph changes: " << heights << " heights, " << colors << " RGB samples, "
              << tiles << " base tile blocks; alpha, draw masks, flags and overlay IDs identical\n";
    return heights && colors && tiles && edited.colour[center * 3] == 0x31 &&
        edited.colour[center * 3 + 1] == 0x57 && edited.colour[center * 3 + 2] == 0x9a &&
        (edited.textures[block] & 15) == ((base.textures[block] + 1) & 15) ? 0 : 1;
}

int main(int argc, char** argv) {
    const bool graph = argc == 4 && std::string(argv[3]) == "--graph";
    const bool heights_only = argc == 4 && std::string(argv[3]) == "--heights-only";
    if (argc != 2 && argc != 3 && !graph && !heights_only) {
        std::cerr << "Pass original TER and optionally its edited export, with --graph for the material graph fixture or --heights-only for a generic height-diff.\n";
        return 2;
    }
    const auto start = std::chrono::steady_clock::now();
    vrv::terrain::Grid base;
    if (!read(argv[1], base)) return 1;
    const auto elapsed = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - start);
    std::cout << "Oracle TER decode " << base.width << " x " << base.depth
              << " at [" << base.minX << ", " << base.minZ << "]: " << elapsed.count() << " ms\n";
    if (argc == 2) return 0;

    vrv::terrain::Grid edited;
    if (!read(argv[2], edited)) return 1;
    if (base.minX != edited.minX || base.minZ != edited.minZ ||
        base.width != edited.width || base.depth != edited.depth ||
        base.flags != edited.flags || base.drawn != edited.drawn) return 1;
    for (int layer = 0; layer < 3; ++layer) {
        if (base.alpha[layer] != edited.alpha[layer]) return 1;
    }
    if (graph) return verify_graph(base, edited);
    if (heights_only) {
        if (base.minX != edited.minX || base.minZ != edited.minZ ||
            base.width != edited.width || base.depth != edited.depth) return 1;
        if (base.colour != edited.colour || base.textures != edited.textures) return 1;
        if (base.flags != edited.flags || base.drawn != edited.drawn) return 1;
        for (int layer = 0; layer < 3; ++layer) {
            if (base.alpha[layer] != edited.alpha[layer]) return 1;
        }
        size_t changed = 0;
        for (size_t i = 0; i < base.Count(); ++i) changed += base.height[i] != edited.height[i];
        std::cout << "HeightsOnly: changed " << changed
                  << "; non-height layers identical; grid " << base.width << " x " << base.depth << "\n";
        return 0;
    }
    if (base.colour != edited.colour || base.textures != edited.textures) return 1;

    const auto center = base.At(-base.minX, -base.minZ);
    if (center >= base.Count()) return 1;
    size_t changed = 0;
    for (size_t i = 0; i < base.Count(); ++i) {
        if (base.height[i] == edited.height[i]) continue;
        const auto dx = static_cast<int>(i % base.width) + base.minX;
        const auto dz = static_cast<int>(i / base.width) + base.minZ;
        if (dx * dx + dz * dz >= 24 * 24) return 1;
        ++changed;
    }
    std::cout << "Center: " << base.height[center] << " -> " << edited.height[center]
              << "; changed heights: " << changed << "; non-height layers identical\n";
    return changed == 1747 && std::abs(edited.height[center] - base.height[center] - 24) < 0.05 ? 0 : 1;
}
