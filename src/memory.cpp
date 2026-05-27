#include <array>
#include <fstream>
#include <map>
#include <spdlog/spdlog.h>
#include <string>
#include <unistd.h>
#include <vector>

#include "memory.h"
#include "file_utils.h"
#include "hud_elements.h"

float memused, memmax, swapused;
int mem_temp, memclock, membandwidth;
uint64_t proc_mem_resident, proc_mem_shared, proc_mem_virt;

static bool read_int64_sysfs(const std::string& path, int64_t& value) {
    const std::string line = read_line(path);
    if (line.empty())
        return false;

    try {
        value = std::stoll(line);
        return true;
    } catch (...) {
        return false;
    }
}

void update_meminfo() {
    std::ifstream file("/proc/meminfo");
    std::map<std::string, float> meminfo;

    if (!file.is_open()) {
        SPDLOG_ERROR("can't open /proc/meminfo");
        return;
    }

    for (std::string line; std::getline(file, line);) {
        auto key = line.substr(0, line.find(":"));
        auto val = line.substr(key.length() + 2);
        meminfo[key] = std::stoull(val) / 1024.f / 1024.f;
    }

    memmax = meminfo["MemTotal"];
    memused = meminfo["MemTotal"] - meminfo["MemAvailable"];
    swapused = meminfo["SwapTotal"] - meminfo["SwapFree"];

    int64_t emc_clock = 0;
    if (read_int64_sysfs("/sys/kernel/debug/clk/emc/clk_rate", emc_clock))
        memclock = emc_clock / 1000000;
    else
        memclock = 0;

    int64_t mc_activity = 0;
    if (memclock > 0 && read_int64_sysfs("/sys/kernel/actmon_avg_activity/mc_all", mc_activity))
        membandwidth = mc_activity / memclock / 10;
    else
        membandwidth = 0;
}

void update_mem_temp() {
    static bool inited = false;
    static std::vector<std::ifstream> mem_temp_files;

    if (!inited) {
        inited = true;
        std::string path = "/sys/class/hwmon/";
        auto dirs = ls(path.c_str(), "hwmon", LS_DIRS);
        for (auto &dir : dirs) {
            if (read_line(path + dir + "/name") == "spd5118")
                mem_temp_files.emplace_back(path + dir + "/temp1_input");
        }
        if (mem_temp_files.empty())
            SPDLOG_ERROR("failed to find known ram temp sensors");
    }

    int temp = 0;
    for (auto &file : mem_temp_files) {
        int _temp;
        file.clear();
        file.seekg(0);
        if ((file >> _temp) && _temp > temp)
            temp = _temp;
    }
    mem_temp = temp / 1000;
}

void update_procmem()
{
    auto page_size = sysconf(_SC_PAGESIZE);
    if (page_size < 0) page_size = 4096;

    std::string f = "/proc/";

    {
        auto gs_pid = HUDElements.g_gamescopePid;
        f += gs_pid < 1 ? "self" : std::to_string(gs_pid);
        f += "/statm";
    }

    std::ifstream file(f);

    if (!file.is_open()) {
        SPDLOG_ERROR("can't open {}", f);
        return;
    }

    size_t last_idx = 0;
    std::string line;
    std::getline(file, line);

    if (line.empty())
        return;

    std::array<uint64_t, 3> meminfo;

    for (auto i = 0; i < 3; i++) {
        auto idx = line.find(" ", last_idx);
        auto val = line.substr(last_idx, idx);

        meminfo[i] = std::stoull(val) * page_size;
        last_idx = idx + 1;
    }

    proc_mem_virt = meminfo[0];
    proc_mem_resident = meminfo[1];
    proc_mem_shared = meminfo[2];
}
