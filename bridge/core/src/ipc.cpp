#include "vrmc/ipc.hpp"

#include <cstring>

#ifdef _WIN32
#include <Windows.h>
#else
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>
#endif

namespace vrmc {

#ifdef _WIN32
IpcWriter::IpcWriter(const std::string& name) {
    handle_ = CreateFileMappingA(
        INVALID_HANDLE_VALUE, nullptr, PAGE_READWRITE | SEC_COMMIT,
        static_cast<DWORD>((sizeof(SharedLayout) + 0xFFFFFFFF) >> 32),
        static_cast<DWORD>(sizeof(SharedLayout)), name.c_str());
    if (handle_ == nullptr) return;
    layout_ = static_cast<SharedLayout*>(MapViewOfFile(handle_, FILE_MAP_ALL_ACCESS, 0, 0, sizeof(SharedLayout)));
    if (layout_ != nullptr) {
        std::memset(layout_, 0, sizeof(SharedLayout));
        layout_->snapshot.magic = kIpcMagic;
        layout_->snapshot.version = kIpcVersion;
    }
}

IpcWriter::~IpcWriter() {
    if (layout_ != nullptr) UnmapViewOfFile(layout_);
    if (handle_ != nullptr) CloseHandle(handle_);
}

IpcReader::IpcReader(const std::string& name) {
    handle_ = OpenFileMappingA(FILE_MAP_READ, FALSE, name.c_str());
    if (handle_ == nullptr) return;
    layout_ = static_cast<SharedLayout*>(MapViewOfFile(handle_, FILE_MAP_READ, 0, 0, sizeof(SharedLayout)));
}

IpcReader::~IpcReader() {
    if (layout_ != nullptr) UnmapViewOfFile(layout_);
    if (handle_ != nullptr) CloseHandle(handle_);
}
#else
IpcWriter::IpcWriter(const std::string& name) : name_(name) {
    fd_ = ::shm_open(name.c_str(), O_CREAT | O_RDWR, 0600);
    if (fd_ < 0) return;
    if (ftruncate(fd_, static_cast<off_t>(sizeof(SharedLayout))) != 0) {
        ::close(fd_); fd_ = -1; return;
    }
    void* memory = mmap(nullptr, sizeof(SharedLayout), PROT_READ | PROT_WRITE, MAP_SHARED, fd_, 0);
    if (memory == MAP_FAILED) return;
    layout_ = static_cast<SharedLayout*>(memory);
    std::memset(layout_, 0, sizeof(SharedLayout));
    layout_->snapshot.magic = kIpcMagic;
    layout_->snapshot.version = kIpcVersion;
}

IpcWriter::~IpcWriter() {
    if (layout_ != nullptr) munmap(layout_, sizeof(SharedLayout));
    if (fd_ >= 0) ::close(fd_);
    if (!name_.empty()) ::shm_unlink(name_.c_str());
}

IpcReader::IpcReader(const std::string& name) : name_(name) {
    fd_ = ::shm_open(name.c_str(), O_RDWR, 0600);
    if (fd_ < 0) return;
    void* memory = mmap(nullptr, sizeof(SharedLayout), PROT_READ | PROT_WRITE, MAP_SHARED, fd_, 0);
    if (memory == MAP_FAILED) return;
    layout_ = static_cast<SharedLayout*>(memory);
}

IpcReader::~IpcReader() {
    if (layout_ != nullptr) munmap(layout_, sizeof(SharedLayout));
    if (fd_ >= 0) ::close(fd_);
}
#endif

void IpcWriter::write(const IpcSnapshot& snapshot) noexcept {
    if (layout_ == nullptr) return;
    std::atomic_ref<uint32_t> seq(layout_->seqlock);
    const uint32_t start = seq.load(std::memory_order_relaxed);
    seq.store(start | 1u, std::memory_order_release);
    std::atomic_thread_fence(std::memory_order_release);
    layout_->snapshot = snapshot;
    seq.store((start | 1u) + 1u, std::memory_order_release);
}

bool IpcReader::read(IpcSnapshot& output) const noexcept {
    if (layout_ == nullptr) return false;
    std::atomic_ref<uint32_t> seq(const_cast<SharedLayout*>(layout_)->seqlock);
    for (int attempt = 0; attempt < 4; ++attempt) {
        const uint32_t first = seq.load(std::memory_order_acquire);
        if ((first & 1u) != 0) continue;
        IpcSnapshot copy = layout_->snapshot;
        std::atomic_thread_fence(std::memory_order_acquire);
        const uint32_t second = seq.load(std::memory_order_relaxed);
        if (first == second && copy.magic == kIpcMagic && copy.version == kIpcVersion) {
            output = copy;
            return true;
        }
    }
    return false;
}

} // namespace vrmc
