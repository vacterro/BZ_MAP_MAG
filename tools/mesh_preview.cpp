// Local adapter built against the operator's VRV checkout. Game assets stay in place.
#include "MeshIcon.h"
#include "MeshSurface.h"

#include <cstring>
#include <filesystem>
#include <fstream>
#include <limits>
#include <string>

namespace fs = std::filesystem;
using vrv::meshicon::Corner;
using vrv::meshicon::Mesh;
using vrv::meshicon::Surface;

static bool read_mesh(const std::string& bytes, Mesh& mesh) {
    if (vrv::meshicon::Read(bytes, mesh)) return true;
    vrv::meshsurface::Shape shape;
    if (!vrv::meshsurface::Read(bytes, 1.0f, shape)) return false;
    mesh = {};
    for (const auto& triangle : shape.triangles) {
        const float* a = triangle.a;
        const float* b = triangle.e1;
        const float* c = triangle.e2;
        const float x = b[1] * c[2] - b[2] * c[1];
        const float y = b[2] * c[0] - b[0] * c[2];
        const float z = b[0] * c[1] - b[1] * c[0];
        const float length = std::sqrt(x*x + y*y + z*z);
        if (!std::isfinite(length) || length <= std::numeric_limits<float>::epsilon()) continue;
        const float nx = x / length, ny = y / length, nz = z / length;
        mesh.corners.push_back({a[0], a[1], a[2], nx, ny, nz, 0, 0});
        mesh.corners.push_back({a[0]+b[0], a[1]+b[1], a[2]+b[2], nx, ny, nz, 0, 0});
        mesh.corners.push_back({a[0]+c[0], a[1]+c[1], a[2]+c[2], nx, ny, nz, 0, 0});
    }
    if (mesh.corners.empty()) return false;
    Surface surface;
    surface.count = mesh.corners.size();
    mesh.surfaces.push_back(surface);
    return true;
}

static void word(std::ostream& output, uint32_t value) {
    const char bytes[] = {static_cast<char>(value), static_cast<char>(value >> 8),
        static_cast<char>(value >> 16), static_cast<char>(value >> 24)};
    output.write(bytes, sizeof(bytes));
}

static void real(std::ostream& output, float value) {
    uint32_t bits;
    static_assert(sizeof(bits) == sizeof(value));
    std::memcpy(&bits, &value, sizeof(value));
    word(output, bits);
}

static std::string read_file(const fs::path& source) {
    std::ifstream input(source, std::ios::binary | std::ios::ate);
    if (!input) return {};
    const auto size = input.tellg();
    if (size <= 0 || size > 64 * 1024 * 1024) return {};
    std::string bytes(static_cast<size_t>(size), '\0');
    input.seekg(0);
    return input.read(bytes.data(), size) ? bytes : std::string();
}

static int convert(const fs::path& source, const fs::path& target) {
    const std::string bytes = read_file(source);
    Mesh mesh;
    if (!read_mesh(bytes, mesh) || mesh.surfaces.empty()) return 3;
    std::ofstream output(target, std::ios::binary);
    if (!output) return 4;
    output.write("BZM1", 4);
    word(output, static_cast<uint32_t>(mesh.surfaces.size()));
    for (const auto& surface : mesh.surfaces) {
        const auto& binding = surface.texture.empty() ? surface.material : surface.texture;
        word(output, static_cast<uint32_t>(binding.size()));
        output.write(binding.data(), binding.size());
        word(output, static_cast<uint32_t>(surface.count));
        for (float channel : surface.diffuse) real(output, channel);
        for (size_t i = surface.first; i < surface.first + surface.count; ++i) {
            const Corner& p = mesh.corners[i];
            for (float field : {p.x, p.y, p.z, p.nx, p.ny, p.nz, p.u, p.v}) real(output, field);
        }
    }
    output.close();
    return output ? 0 : 4;
}

static int convert_texture(const fs::path& source, const fs::path& target) {
    vrv::crosshair::Picture image;
    if (!vrv::crosshair::DecodeDds(read_file(source), image, 512)) return 3;
    std::ofstream output(target, std::ios::binary);
    if (!output) return 4;
    output.write("BZT1", 4);
    word(output, image.w);
    word(output, image.h);
    output.write(reinterpret_cast<const char*>(image.rgba.data()), image.rgba.size());
    output.close();
    return output ? 0 : 4;
}

#ifdef _WIN32
int wmain(int argc, wchar_t** argv) {
#else
int main(int argc, char** argv) {
#endif
    if (argc == 3) return convert(argv[1], argv[2]);
    if (argc == 4 && fs::path(argv[1]) == "--dds") return convert_texture(argv[2], argv[3]);
    return 1;
}
