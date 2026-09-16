// Vulkan device-creation diagnostic probe (32-bit x86).
// Loads vulkan-1.dll at runtime. Global functions (vkCreateInstance etc.)
// are obtained via vkGetInstanceProcAddr(NULL, name) — NOT GetProcAddress,
// because vulkan-1.dll only exports vkGetInstanceProcAddr + the enum funcs.
#define VK_NO_PROTOTYPES
#define VK_USE_PLATFORM_WIN32_KHR 1
#include <vulkan/vulkan.h>
#include <windows.h>
#include <cstdio>
#include <cstring>
#include <vector>
#include <string>

// Function pointers
static PFN_vkGetInstanceProcAddr vkGetInstanceProcAddr = nullptr;
static PFN_vkEnumerateInstanceExtensionProperties vkEnumerateInstanceExtensionProperties = nullptr;
static PFN_vkCreateInstance vkCreateInstance = nullptr;
static PFN_vkEnumeratePhysicalDevices vkEnumeratePhysicalDevices = nullptr;
static PFN_vkGetPhysicalDeviceProperties vkGetPhysicalDeviceProperties = nullptr;
static PFN_vkEnumerateDeviceExtensionProperties vkEnumerateDeviceExtensionProperties = nullptr;
static PFN_vkGetPhysicalDeviceQueueFamilyProperties vkGetPhysicalDeviceQueueFamilyProperties = nullptr;
static PFN_vkCreateDevice vkCreateDevice = nullptr;
static PFN_vkDestroyDevice vkDestroyDevice = nullptr;
static PFN_vkDestroyInstance vkDestroyInstance = nullptr;

static FILE* g_log = nullptr;

static void Log(const char* fmt, ...) {
    va_list a; va_start(a, fmt);
    vfprintf(g_log, fmt, a);
    vprintf(fmt, a);
    fflush(g_log);
    va_end(a);
}

int WINAPI WinMain(HINSTANCE, HINSTANCE, LPSTR, int) {
    g_log = fopen("vulkan_probe.log", "w");
    if (!g_log) g_log = stdout;
    Log("=== Vulkan Device Creation Probe (32-bit) ===\n\n");

    // Load vulkan-1.dll (the Vulkan loader)
    HMODULE vulkanDll = LoadLibraryA("vulkan-1.dll");
    if (!vulkanDll) { Log("Failed to load vulkan-1.dll (err=%lu)\n", GetLastError()); return 1; }
    Log("Loaded vulkan-1.dll at %p\n", vulkanDll);

    // vkGetInstanceProcAddr IS exported by vulkan-1.dll
    vkGetInstanceProcAddr = (PFN_vkGetInstanceProcAddr)GetProcAddress(vulkanDll, "vkGetInstanceProcAddr");
    if (!vkGetInstanceProcAddr) { Log("vkGetInstanceProcAddr not found in vulkan-1.dll\n"); return 1; }
    Log("vkGetInstanceProcAddr = %p\n", vkGetInstanceProcAddr);

    // vkEnumerateInstanceExtensionProperties is also exported directly
    vkEnumerateInstanceExtensionProperties = (PFN_vkEnumerateInstanceExtensionProperties)GetProcAddress(vulkanDll, "vkEnumerateInstanceExtensionProperties");
    if (!vkEnumerateInstanceExtensionProperties) {
        // Try via vkGetInstanceProcAddr with null instance
        vkEnumerateInstanceExtensionProperties = (PFN_vkEnumerateInstanceExtensionProperties)vkGetInstanceProcAddr(VK_NULL_HANDLE, "vkEnumerateInstanceExtensionProperties");
    }
    Log("vkEnumerateInstanceExtensionProperties = %p\n", vkEnumerateInstanceExtensionProperties);

    // Load global-level functions via vkGetInstanceProcAddr(NULL, name)
    vkCreateInstance = (PFN_vkCreateInstance)vkGetInstanceProcAddr(VK_NULL_HANDLE, "vkCreateInstance");
    Log("vkCreateInstance = %p\n", vkCreateInstance);
    if (!vkCreateInstance) { Log("FAILED to load vkCreateInstance\n"); return 1; }

    // 1. Create instance
    VkInstanceCreateInfo ici = {};
    ici.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
    const char* instExts[] = {
        VK_KHR_SURFACE_EXTENSION_NAME,
        VK_KHR_WIN32_SURFACE_EXTENSION_NAME,
        VK_KHR_GET_PHYSICAL_DEVICE_PROPERTIES_2_EXTENSION_NAME,
        VK_KHR_GET_SURFACE_CAPABILITIES_2_EXTENSION_NAME,
        VK_KHR_EXTERNAL_MEMORY_CAPABILITIES_EXTENSION_NAME,
        VK_KHR_EXTERNAL_SEMAPHORE_CAPABILITIES_EXTENSION_NAME,
        VK_KHR_EXTERNAL_FENCE_CAPABILITIES_EXTENSION_NAME,
        "VK_KHR_surface_maintenance1",
    };
    ici.enabledExtensionCount = 8;
    ici.ppEnabledExtensionNames = instExts;

    VkInstance inst = VK_NULL_HANDLE;
    Log("Calling vkCreateInstance...\n");
    VkResult r = vkCreateInstance(&ici, nullptr, &inst);
    Log("vkCreateInstance: %d (%s)\n", r, r == VK_SUCCESS ? "OK" : "FAILED");
    if (r != VK_SUCCESS) { Log("Cannot continue without instance.\n"); fclose(g_log); return 1; }

    // Load instance-level functions
    vkEnumeratePhysicalDevices = (PFN_vkEnumeratePhysicalDevices)vkGetInstanceProcAddr(inst, "vkEnumeratePhysicalDevices");
    vkGetPhysicalDeviceProperties = (PFN_vkGetPhysicalDeviceProperties)vkGetInstanceProcAddr(inst, "vkGetPhysicalDeviceProperties");
    vkEnumerateDeviceExtensionProperties = (PFN_vkEnumerateDeviceExtensionProperties)vkGetInstanceProcAddr(inst, "vkEnumerateDeviceExtensionProperties");
    vkGetPhysicalDeviceQueueFamilyProperties = (PFN_vkGetPhysicalDeviceQueueFamilyProperties)vkGetInstanceProcAddr(inst, "vkGetPhysicalDeviceQueueFamilyProperties");
    vkCreateDevice = (PFN_vkCreateDevice)vkGetInstanceProcAddr(inst, "vkCreateDevice");
    vkDestroyDevice = (PFN_vkDestroyDevice)vkGetInstanceProcAddr(inst, "vkDestroyDevice");
    vkDestroyInstance = (PFN_vkDestroyInstance)vkGetInstanceProcAddr(inst, "vkDestroyInstance");
    Log("Instance functions loaded (vkCreateDevice=%p)\n", vkCreateDevice);

    // 2. Enumerate physical devices
    uint32_t gpuCount = 0;
    vkEnumeratePhysicalDevices(inst, &gpuCount, nullptr);
    std::vector<VkPhysicalDevice> gpus(gpuCount);
    vkEnumeratePhysicalDevices(inst, &gpuCount, gpus.data());
    Log("Found %u physical devices:\n", gpuCount);

    for (uint32_t g = 0; g < gpuCount; g++) {
        VkPhysicalDeviceProperties props;
        vkGetPhysicalDeviceProperties(gpus[g], &props);
        Log("  [%u] %s (driver 0x%x, api %u.%u.%u)\n",
            g, props.deviceName, props.driverVersion,
            VK_VERSION_MAJOR(props.apiVersion), VK_VERSION_MINOR(props.apiVersion), VK_VERSION_PATCH(props.apiVersion));
    }

    VkPhysicalDevice phys = gpus[0];

    // 3. Enumerate ALL device extensions
    uint32_t extCount = 0;
    vkEnumerateDeviceExtensionProperties(phys, nullptr, &extCount, nullptr);
    std::vector<VkExtensionProperties> exts(extCount);
    vkEnumerateDeviceExtensionProperties(phys, nullptr, &extCount, exts.data());
    Log("\nDevice reports %u extensions supported:\n", extCount);
    std::vector<std::string> allExtNames;
    for (auto& e : exts) {
        Log("  %s\n", e.extensionName);
        allExtNames.push_back(e.extensionName);
    }

    // 4. The FULL set DXVK 3.1 requests
    const char* dxvkFullSet[] = {
        "VK_EXT_attachment_feedback_loop_layout","VK_EXT_border_color_swizzle",
        "VK_EXT_conservative_rasterization","VK_EXT_custom_border_color",
        "VK_EXT_depth_clip_enable","VK_EXT_depth_bias_control",
        "VK_EXT_descriptor_heap","VK_EXT_dynamic_rendering_unused_attachments",
        "VK_EXT_extended_dynamic_state3","VK_EXT_fragment_shader_interlock",
        "VK_EXT_graphics_pipeline_library","VK_EXT_hdr_metadata",
        "VK_EXT_line_rasterization","VK_EXT_memory_priority",
        "VK_EXT_multi_draw","VK_EXT_non_seamless_cube_map",
        "VK_EXT_pageable_device_local_memory","VK_EXT_robustness2",
        "VK_EXT_sample_locations","VK_EXT_shader_module_identifier",
        "VK_EXT_transform_feedback","VK_EXT_vertex_attribute_divisor",
        "VK_KHR_dynamic_rendering_local_read","VK_KHR_external_memory_win32",
        "VK_KHR_external_semaphore_win32","VK_KHR_incremental_present",
        "VK_KHR_load_store_op_none","VK_KHR_maintenance5",
        "VK_KHR_maintenance6","VK_KHR_maintenance8",
        "VK_KHR_maintenance9","VK_KHR_maintenance10",
        "VK_KHR_maintenance11","VK_KHR_pipeline_library",
        "VK_KHR_present_id","VK_KHR_present_wait",
        "VK_KHR_shader_float_controls2","VK_KHR_shader_subgroup_uniform_control_flow",
        "VK_KHR_shader_untyped_pointers","VK_KHR_swapchain",
        "VK_KHR_swapchain_maintenance1","VK_KHR_swapchain_mutable_format",
        "VK_KHR_unified_image_layouts","VK_KHR_win32_keyed_mutex",
        "VK_NV_raw_access_chains",
    };
    const size_t fullCount = sizeof(dxvkFullSet)/sizeof(dxvkFullSet[0]);

    // 5. Find graphics queue
    uint32_t qfCount = 0;
    vkGetPhysicalDeviceQueueFamilyProperties(phys, &qfCount, nullptr);
    std::vector<VkQueueFamilyProperties> qfs(qfCount);
    vkGetPhysicalDeviceQueueFamilyProperties(phys, &qfCount, qfs.data());
    uint32_t graphicsQf = 0xFFFFFFFF;
    for (uint32_t i = 0; i < qfCount; i++) {
        if (qfs[i].queueFlags & VK_QUEUE_GRAPHICS_BIT) { graphicsQf = i; break; }
    }
    Log("\nGraphics queue family: %u\n", graphicsQf);
    if (graphicsQf == 0xFFFFFFFF) { Log("NO GRAPHICS QUEUE!\n"); fclose(g_log); return 1; }

    // EXPERIMENT 1: Full DXVK set
    Log("\n--- EXPERIMENT 1: Full DXVK 3.1 set (%zu exts) ---\n", fullCount);
    {
        float prio = 1.0f;
        VkDeviceQueueCreateInfo qci = {}; qci.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
        qci.queueFamilyIndex = graphicsQf; qci.queueCount = 1; qci.pQueuePriorities = &prio;
        VkDeviceCreateInfo dci = {}; dci.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
        dci.queueCreateInfoCount = 1; dci.pQueueCreateInfos = &qci;
        dci.enabledExtensionCount = (uint32_t)fullCount; dci.ppEnabledExtensionNames = dxvkFullSet;
        VkDevice dev = VK_NULL_HANDLE;
        r = vkCreateDevice(phys, &dci, nullptr, &dev);
        Log("Result: %d (%s)\n", r, r == VK_SUCCESS ? "SUCCESS" : "FAILED");
        if (dev) vkDestroyDevice(dev, nullptr);
    }

    // EXPERIMENT 2: Incremental (add one at a time)
    Log("\n--- EXPERIMENT 2: Incremental ---\n");
    for (size_t i = 0; i < fullCount; i++) {
        float prio = 1.0f;
        VkDeviceQueueCreateInfo qci = {}; qci.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
        qci.queueFamilyIndex = graphicsQf; qci.queueCount = 1; qci.pQueuePriorities = &prio;
        VkDeviceCreateInfo dci = {}; dci.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
        dci.queueCreateInfoCount = 1; dci.pQueueCreateInfos = &qci;
        dci.enabledExtensionCount = (uint32_t)(i+1); dci.ppEnabledExtensionNames = dxvkFullSet;
        VkDevice dev = VK_NULL_HANDLE;
        r = vkCreateDevice(phys, &dci, nullptr, &dev);
        if (dev) vkDestroyDevice(dev, nullptr);
        if (r != VK_SUCCESS) { Log("  FAILED at ext %zu: %s -> %d\n", i, dxvkFullSet[i], r); break; }
        Log("  OK through %zu: %s\n", i, dxvkFullSet[i]);
    }

    // EXPERIMENT 3: Each extension individually
    Log("\n--- EXPERIMENT 3: Each extension individually ---\n");
    for (size_t i = 0; i < fullCount; i++) {
        float prio = 1.0f;
        VkDeviceQueueCreateInfo qci = {}; qci.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
        qci.queueFamilyIndex = graphicsQf; qci.queueCount = 1; qci.pQueuePriorities = &prio;
        VkDeviceCreateInfo dci = {}; dci.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
        dci.queueCreateInfoCount = 1; dci.pQueueCreateInfos = &qci;
        dci.enabledExtensionCount = 1; dci.ppEnabledExtensionNames = &dxvkFullSet[i];
        VkDevice dev = VK_NULL_HANDLE;
        r = vkCreateDevice(phys, &dci, nullptr, &dev);
        if (dev) vkDestroyDevice(dev, nullptr);
        if (r != VK_SUCCESS) Log("  INDIVIDUAL FAIL: %s -> %d\n", dxvkFullSet[i], r);
    }

    // EXPERIMENT 4: Minimal (swapchain only)
    Log("\n--- EXPERIMENT 4: Minimal (swapchain only) ---\n");
    {
        float prio = 1.0f;
        VkDeviceQueueCreateInfo qci = {}; qci.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
        qci.queueFamilyIndex = graphicsQf; qci.queueCount = 1; qci.pQueuePriorities = &prio;
        VkDeviceCreateInfo dci = {}; dci.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
        dci.queueCreateInfoCount = 1; dci.pQueueCreateInfos = &qci;
        const char* minimal[] = { "VK_KHR_swapchain" };
        dci.enabledExtensionCount = 1; dci.ppEnabledExtensionNames = minimal;
        VkDevice dev = VK_NULL_HANDLE;
        r = vkCreateDevice(phys, &dci, nullptr, &dev);
        Log("Result: %d (%s)\n", r, r == VK_SUCCESS ? "SUCCESS" : "FAILED");
        if (dev) vkDestroyDevice(dev, nullptr);
    }

    // EXPERIMENT 5: Enumerate vs Create discrepancy (all exts)
    // Per-extension progress is logged BEFORE the call: a hard crash in the
    // Unix thunk kills the process silently, and the last flushed line then
    // names the offending extension.
    Log("\n--- EXPERIMENT 5: Enumerate vs Create discrepancy ---\n");
    int discrepancyCount = 0;
    size_t idx = 0;
    for (auto& name : allExtNames) {
        Log("  [%zu/%zu] testing %s\n", idx + 1, allExtNames.size(), name.c_str());
        float prio = 1.0f;
        VkDeviceQueueCreateInfo qci = {}; qci.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
        qci.queueFamilyIndex = graphicsQf; qci.queueCount = 1; qci.pQueuePriorities = &prio;
        VkDeviceCreateInfo dci = {}; dci.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
        dci.queueCreateInfoCount = 1; dci.pQueueCreateInfos = &qci;
        const char* extName = name.c_str();
        dci.enabledExtensionCount = 1; dci.ppEnabledExtensionNames = &extName;
        VkDevice dev = VK_NULL_HANDLE;
        r = vkCreateDevice(phys, &dci, nullptr, &dev);
        if (dev) vkDestroyDevice(dev, nullptr);
        if (r != VK_SUCCESS) { Log("  DISCREPANCY: %s -> %d\n", extName, r); discrepancyCount++; }
        idx++;
    }
    Log("(%d discrepancies found)\n", discrepancyCount);

    // EXPERIMENT 6: Wine VR ICD extensions individually.
    // The console of the previous run showed a hard vkCreateDevice crash
    // (0xc0000005 in Unix call) inside GE-Proton's xalia companion while its
    // OpenVR/OpenXR extension providers were active, and the device reports
    // VK_WINE_openvr/openxr_device_extensions. Test them in isolation.
    Log("\n--- EXPERIMENT 6: Wine VR ICD extensions individually ---\n");
    {
        const char* wineVr[] = { "VK_WINE_openvr_device_extensions", "VK_WINE_openxr_device_extensions" };
        for (size_t i = 0; i < 2; i++) {
            Log("  testing alone: %s\n", wineVr[i]);
            float prio = 1.0f;
            VkDeviceQueueCreateInfo qci = {}; qci.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
            qci.queueFamilyIndex = graphicsQf; qci.queueCount = 1; qci.pQueuePriorities = &prio;
            VkDeviceCreateInfo dci = {}; dci.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
            dci.queueCreateInfoCount = 1; dci.pQueueCreateInfos = &qci;
            dci.enabledExtensionCount = 1; dci.ppEnabledExtensionNames = &wineVr[i];
            VkDevice dev = VK_NULL_HANDLE;
            r = vkCreateDevice(phys, &dci, nullptr, &dev);
            if (dev) vkDestroyDevice(dev, nullptr);
            Log("  %s -> %d (%s)\n", wineVr[i], r, r == VK_SUCCESS ? "SUCCESS" : "FAILED");
        }
    }

    // EXPERIMENT 7: Full DXVK set + Wine OpenXR device extension combined.
    // If DXVK's D3D11 path ever requests the OpenXR-augmented extensions the
    // game process could hit the same crash; this probes that combination.
    Log("\n--- EXPERIMENT 7: Full DXVK set + VK_WINE_openxr_device_extensions ---\n");
    {
        std::vector<const char*> combined(dxvkFullSet, dxvkFullSet + fullCount);
        combined.push_back("VK_WINE_openxr_device_extensions");
        Log("  testing %zu extensions together\n", combined.size());
        float prio = 1.0f;
        VkDeviceQueueCreateInfo qci = {}; qci.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
        qci.queueFamilyIndex = graphicsQf; qci.queueCount = 1; qci.pQueuePriorities = &prio;
        VkDeviceCreateInfo dci = {}; dci.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
        dci.queueCreateInfoCount = 1; dci.pQueueCreateInfos = &qci;
        dci.enabledExtensionCount = (uint32_t)combined.size(); dci.ppEnabledExtensionNames = combined.data();
        VkDevice dev = VK_NULL_HANDLE;
        r = vkCreateDevice(phys, &dci, nullptr, &dev);
        if (dev) vkDestroyDevice(dev, nullptr);
        Log("Result: %d (%s)\n", r, r == VK_SUCCESS ? "SUCCESS" : "FAILED");
    }

    vkDestroyInstance(inst, nullptr);
    Log("\n=== Probe complete ===\n");
    if (g_log && g_log != stdout) fclose(g_log);
    return 0;
}
