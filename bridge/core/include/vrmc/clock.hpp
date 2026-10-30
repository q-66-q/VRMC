#pragma once

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <optional>
#include <vector>

namespace vrmc {

struct ClockSample {
    uint64_t t0 = 0;
    uint64_t t1 = 0;
    uint64_t t2 = 0;
    uint64_t t3 = 0;

    [[nodiscard]] int64_t offset() const {
        const int64_t forward = static_cast<int64_t>(t1 - t0);
        const int64_t backward = static_cast<int64_t>(t2 - t3);
        return (forward + backward) / 2;
    }
    [[nodiscard]] int64_t roundTrip() const {
        return static_cast<int64_t>(t3 - t0) - static_cast<int64_t>(t2 - t1);
    }
    [[nodiscard]] bool valid() const {
        return roundTrip() >= 0 && roundTrip() < 2'000'000'000;
    }
};

struct ClockEstimate {
    int64_t offset = 0;
    int64_t roundTrip = 0;
    int64_t uncertainty = 0;
    size_t samples = 0;
};

/// Median offset estimator; intentionally small and deterministic for parity tests with
/// the Swift implementation.
class ClockSyncEstimator {
public:
    explicit ClockSyncEstimator(size_t capacity = 64) : capacity_(capacity < 8 ? 8 : capacity) {}

    void reset() { samples_.clear(); }
    bool add(const ClockSample& sample) {
        if (!sample.valid()) return false;
        samples_.push_back(sample);
        if (samples_.size() > capacity_) {
            samples_.erase(samples_.begin(), samples_.begin() + static_cast<ptrdiff_t>(samples_.size() - capacity_));
        }
        return true;
    }
    [[nodiscard]] std::optional<ClockEstimate> latest() const {
        if (samples_.empty()) return std::nullopt;
        std::vector<int64_t> offsets;
        std::vector<int64_t> rtts;
        for (const auto& sample : samples_) {
            offsets.push_back(sample.offset());
            rtts.push_back(sample.roundTrip());
        }
        std::sort(offsets.begin(), offsets.end());
        std::sort(rtts.begin(), rtts.end());
        const int64_t medianOffset = offsets[offsets.size() / 2];
        const int64_t medianRtt = rtts[rtts.size() / 2];
        return ClockEstimate{medianOffset, medianRtt, medianRtt / 2, samples_.size()};
    }
    [[nodiscard]] std::optional<uint64_t> hostToClient(uint64_t host) const {
        auto estimate = latest();
        if (!estimate) return std::nullopt;
        return static_cast<uint64_t>(static_cast<int64_t>(host) - estimate->offset);
    }
    [[nodiscard]] std::optional<uint64_t> clientToHost(uint64_t client) const {
        auto estimate = latest();
        if (!estimate) return std::nullopt;
        return static_cast<uint64_t>(static_cast<int64_t>(client) + estimate->offset);
    }

private:
    std::vector<ClockSample> samples_;
    size_t capacity_;
};

} // namespace vrmc
