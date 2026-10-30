#include "file_source.hpp"

#include <fstream>
#include <iterator>

namespace vrmc {
namespace {
struct Nal {
    size_t offset = 0;
    size_t length = 0;
    uint8_t type = 0;
};

std::vector<Nal> splitAnnexB(const std::vector<uint8_t>& data) {
    std::vector<size_t> starts;
    for (size_t i = 0; i + 2 < data.size();) {
        if (data[i] == 0 && data[i + 1] == 0 && data[i + 2] == 1) {
            starts.push_back(i); i += 3;
        } else if (i + 3 < data.size() && data[i] == 0 && data[i + 1] == 0 && data[i + 2] == 0 && data[i + 3] == 1) {
            starts.push_back(i); i += 4;
        } else {
            ++i;
        }
    }
    std::vector<Nal> nals;
    for (size_t index = 0; index < starts.size(); ++index) {
        size_t start = starts[index];
        size_t header = (start + 2 < data.size() && data[start + 2] == 1) ? 3 : 4;
        size_t payload = start + header;
        size_t end = index + 1 < starts.size() ? starts[index + 1] : data.size();
        if (payload >= end) continue;
        nals.push_back(Nal{payload, end - payload, static_cast<uint8_t>(data[payload] & 0x1F)});
    }
    return nals;
}
}

bool FileVideoSource::open(const std::string& path, uint32_t fps, std::string& error) {
    std::ifstream input(path, std::ios::binary);
    if (!input) {
        error = "cannot open video file " + path;
        return false;
    }
    std::vector<uint8_t> bytes((std::istreambuf_iterator<char>(input)), std::istreambuf_iterator<char>());
    if (bytes.empty()) {
        error = "video file is empty";
        return false;
    }
    auto nals = splitAnnexB(bytes);
    if (nals.empty()) {
        error = "no Annex-B NAL units";
        return false;
    }
    std::vector<Nal> current;
    auto flush = [&]() {
        if (current.empty()) return;
        EncodedAccessUnit unit;
        for (auto nal : current) {
            static constexpr uint8_t startCode[4] = {0, 0, 0, 1};
            unit.data.insert(unit.data.end(), startCode, startCode + 4);
            unit.data.insert(unit.data.end(), bytes.begin() + nal.offset, bytes.begin() + nal.offset + nal.length);
            if (nal.type == 5) unit.keyframe = true;
        }
        units_.push_back(std::move(unit));
        current.clear();
    };
    for (auto nal : nals) {
        if (nal.type == 9) {
            flush();
            current.push_back(nal);
        } else {
            current.push_back(nal);
        }
    }
    flush();
    if (units_.empty()) {
        error = "no access units";
        return false;
    }
    fps_ = fps;
    index_ = 0;
    return true;
}

bool FileVideoSource::next(EncodedAccessUnit& output) {
    if (units_.empty()) return false;
    output = units_[index_ % units_.size()];
    output.timestampNs = 0;
    output.frameIndex = index_;
    ++index_;
    return true;
}

void FileVideoSource::rewind() { index_ = 0; }

} // namespace vrmc
