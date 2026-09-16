// Vulkan device-creation diagnostic probe.
// Builds as 32-bit (x86) to match DXHRDC.exe's environment.
// Tries vkCreateDevice with incrementally larger extension sets and reports
// exactly which extension causes VK_ERROR_EXTENSION_NOT_PRESENT.
#define VK_USE_PLATFORM_WIN32_KHR 1
#include <vulkan/vulkan.h>
#include <cstdio>
#include <cstring>
#include <vector>
#include <string>

static FILE* g_log = nullptr;
static void Log(const char* fmt, ...) {
    va_list a; va_start(a, fmt);
    vfprintf(g_log, fmt, a);
    vprintf(fmt, a);
    va_end(a);
}

int WINAPI WinMain(HINSTANCE, HINSTANCE, LPSTR, int) {
    g_log = fopen("vulkan_probe.log", "w");
    if (!g_log) g_log = stdout;
    Log("=== Vulkan Device Creation Probe (32-bit) ===\n\n");

    // 1. Create instance with minimal extensions
    VkInstanceCreateInfo ici = {};
    ici.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
    // Enable the same instance extensions DXVK uses
    const char* instExts[] = {
        VK_KHR_SURFACE_EXTENSION_NAME,
        VK_KHR_WIN32_SURFACE_EXTENSION_NAME,
        VK_KHR_GET_PHYSICAL_DEVICE_PROPERTIES_2_EXTENSION_NAME,
        VK_KHR_GET_SURFACE_CAPABILITIES_2_EXTENSION_NAME,
        VK_KHR_EXTERNAL_MEMORY_CAPABILITIES_EXTENSION_NAME,
        VK_KHR_EXTERNAL_SEMAPHORE_CAPABILITIES_EXTENSION_NAME,
        VK_KHR_EXTERNAL_FENCE_CAPABILITIES_EXTENSION_NAME,
        VK_KHR_SURFACE_MAINTENANCE_1_EXTENSION_NAME,
    };
    ici.enabledExtensionCount = 8;
    ici.ppEnabledExtensionNames = instExts;

    VkInstance inst = VK_NULL_HANDLE;
    VkResult r = vkCreateInstance(&ici, nullptr, &inst);
    Log("vkCreateInstance: %d (%s)\n", r, r == VK_SUCCESS ? "OK" : "FAILED");
    if (r != VK_SUCCESS) { fclose(g_log); return 1; }

    // 2. Enumerate physical devices
    uint32_t gpuCount = 0;
    vkEnumeratePhysicalDevices(inst, &gpuCount, nullptr);
    std::vector<VkPhysicalDevice> gpus(gpuCount);
    vkEnumeratePhysicalDevices(inst, &gpuCount, gpus.data());
    Log("Found %u physical devices:\n", gpuCount);

    for (uint32_t g = 0; g < gpuCount; g++) {
        VkPhysicalDeviceProperties props;
        vkGetPhysicalDeviceProperties(gpus[g], &props);
        Log("  [%u] %s (driver %u.%u.%u, api %u.%u.%u)\n",
            g, props.deviceName,
            VK_VERSION_MAJOR(props.driverVersion), VK_VERSION_MINOR(props.driverVersion), VK_VERSION_PATCH(props.driverVersion),
            VK_VERSION_MAJOR(props.apiVersion), VK_VERSION_MINOR(props.apiVersion), VK_VERSION_PATCH(props.apiVersion));
    }

    // Use device 0
    VkPhysicalDevice phys = gpus[0];

    // 3. Enumerate ALL device extensions — the ground truth
    uint32_t extCount = 0;
    vkEnumerateDeviceExtensionProperties(phys, nullptr, &extCount, nullptr);
    std::vector<VkExtensionProperties> exts(extCount);
    vkEnumerateDeviceExtensionProperties(phys, nullptr, &extCount, exts.data());
    Log("\nDevice reports %u extensions supported:\n", extCount);
    std::vector<std::string> allExtNames;
    for (auto& e : exts) {
        Log("  %s (spec %u.%u.%u)\n", e.extensionName,
            VK_VERSION_MAJOR(e.specVersion), VK_VERSION_MINOR(e.specVersion), VK_VERSION_PATCH(e.specVersion));
        allExtNames.push_back(e.extensionName);
    }

    // 4. The FULL set DXVK 3.1 requests (from the game's log)
    const char* dxvkFullSet[] = {
        VK_EXT_ATTACHMENT_FEEDBACK_LOOP_LAYOUT_EXTENSION_NAME,
        VK_EXT_BORDER_COLOR_SWIZZLE_EXTENSION_NAME,
        VK_EXT_CONSERVATIVE_RASTERIZATION_EXTENSION_NAME,
        VK_EXT_CUSTOM_BORDER_COLOR_EXTENSION_NAME,
        VK_EXT_DEPTH_CLIP_ENABLE_EXTENSION_NAME,
        "VK_EXT_depth_bias_control",
        "VK_EXT_descriptor_heap",
        "VK_EXT_dynamic_rendering_unused_attachments",
        VK_EXT_EXTENDED_DYNAMIC_STATE_3_EXTENSION_NAME,
        VK_EXT_FRAGMENT_SHADER_INTERLOCK_EXTENSION_NAME,
        VK_EXT_GRAPHICS_PIPELINE_LIBRARY_EXTENSION_NAME,
        VK_EXT_HDR_METADATA_EXTENSION_NAME,
        VK_EXT_LINE_RASTERIZATION_EXTENSION_NAME,
        VK_EXT_MEMORY_PRIORITY_EXTENSION_NAME,
        VK_EXT_MULTI_DRAW_EXTENSION_NAME,
        VK_EXT_NON_SEAMLESS_CUBE_MAP_EXTENSION_NAME,
        VK_EXT_PAGEABLE_DEVICE_LOCAL_MEMORY_EXTENSION_NAME,
        VK_EXT_ROBUSTNESS_2_EXTENSION_NAME,
        VK_EXT_SAMPLE_LOCATIONS_EXTENSION_NAME,
        VK_EXT_SHADER_MODULE_IDENTIFIER_EXTENSION_NAME,
        VK_EXT_TRANSFORM_FEEDBACK_EXTENSION_NAME,
        VK_EXT_VERTEX_ATTRIBUTE_DIVISOR_EXTENSION_NAME,
        "VK_KHR_dynamic_rendering_local_read",
        VK_KHR_EXTERNAL_MEMORY_WIN32_EXTENSION_NAME,
        VK_KHR_EXTERNAL_SEMAPHORE_WIN32_EXTENSION_NAME,
        VK_KHR_INCREMENTAL_PRESENT_EXTENSION_NAME,
        VK_KHR_LOAD_STORE_OP_NONE_EXTENSION_NAME,
        VK_KHR_MAINTENANCE_5_EXTENSION_NAME,
        VK_KHR_MAINTENANCE_6_EXTENSION_NAME,
        "VK_KHR_maintenance8",
        "VK_KHR_maintenance9",
        "VK_KHR_maintenance10",
        "VK_KHR_maintenance11",
        VK_KHR_PIPELINE_LIBRARY_EXTENSION_NAME,
        VK_KHR_PRESENT_ID_EXTENSION_NAME,
        VK_KHR_PRESENT_WAIT_EXTENSION_NAME,
        "VK_KHR_shader_float_controls2",
        "VK_KHR_shader_subgroup_uniform_control_flow",
        "VK_KHR_SHADER_UNTYPED_POINTERS_EXTENSION_NAME,
        VK_KHR_SWAPCHAIN_EXTENSION_NAME,
        "VK_KHR_swapchain_maintenance1",
        "VK_KHR_swapchain_mutable_format",
        "VK_KHR_unified_image_layouts",
        VK_KHR_WIN32_KEYED_MUTEX_EXTENSION_NAME,
        "VK_NV_raw_access_chains",
    };
    const size_t fullCount = sizeof(dxvkFullSet)/sizeof(dxvkFullSet[0]);

    // 5. Find a graphics queue family
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

    // 6. EXPERIMENT 1: Try the full DXVK set
    Log("\n--- EXPERIMENT 1: Full DXVK 3.1 extension set (%zu exts) ---\n", fullCount);
    {
        float prio = 1.0f;
        VkDeviceQueueCreateInfo qci = {};
        qci.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
        qci.queueFamilyIndex = graphicsQf;
        qci.queueCount = 1;
        qci.pQueuePriorities = &prio;

        VkDeviceCreateInfo dci = {};
        dci.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
        dci.queueCreateInfoCount = 1;
        dci.pQueueCreateInfos = &qci;
        dci.enabledExtensionCount = (uint32_t)fullCount;
        dci.ppEnabledExtensionNames = dxvkFullSet;

        VkDevice dev = VK_NULL_HANDLE;
        r = vkCreateDevice(phys, &dci, nullptr, &dev);
        Log("Result: %d (%s)\n", r, r == VK_SUCCESS ? "SUCCESS" : "FAILED");
        if (dev) vkDestroyDevice(dev, nullptr);
    }

    // 7. EXPERIMENT 2: Binary search — add extensions one at a time
    Log("\n--- EXPERIMENT 2: Incremental (add one ext at a time) ---\n");
    for (size_t i = 0; i < fullCount; i++) {
        float prio = 1.0f;
        VkDeviceQueueCreateInfo qci = {};
        qci.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
        qci.queueFamilyIndex = graphicsQf;
        qci.queueCount = 1;
        qci.pQueuePriorities = &prio;

        VkDeviceCreateInfo dci = {};
        dci.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
        dci.queueCreateInfoCount = 1;
        dci.pQueueCreateInfos = &qci;
        dci.enabledExtensionCount = (uint32_t)(i + 1);
        dci.ppEnabledExtensionNames = dxvkFullSet;

        VkDevice dev = VK_NULL_HANDLE;
        r = vkCreateDevice(phys, &dci, nullptr, &dev);
        if (dev) vkDestroyDevice(dev, nullptr);
        if (r != VK_SUCCESS) {
            Log("  FAILED at ext %zu: %s -> error %d\n", i, dxvkFullSet[i], r);
            break;
        } else {
            Log("  OK through ext %zu: %s\n", i, dxvkFullSet[i]);
        }
    }

    // 8. EXPERIMENT 3: Try each extension individually
    Log("\n--- EXPERIMENT 3: Each extension individually ---\n");
    for (size_t i = 0; i < fullCount; i++) {
        float prio = 1.0f;
        VkDeviceQueueCreateInfo qci = {};
        qci.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
        qci.queueFamilyIndex = graphicsQf;
        qci.queueCount = 1;
        qci.pQueuePriorities = &prio;

        VkDeviceCreateInfo dci = {};
        dci.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
        dci.queueCreateInfoCount = 1;
        dci.pQueueCreateInfos = &qci;
        dci.enabledExtensionCount = 1;
        dci.ppEnabledExtensionNames = &dxvkFullSet[i];

        VkDevice dev = VK_NULL_HANDLE;
        r = vkCreateDevice(phys, &dci, nullptr, &dev);
        if (dev) vkDestroyDevice(dev, nullptr);
        if (r != VK_SUCCESS) {
            Log("  INDIVIDUAL FAIL: %s -> error %d\n", dxvkFullSet[i], r);
        }
    }

    // 9. EXPERIMENT 4: Empty extension set (just swapchain)
    Log("\n--- EXPERIMENT 4: Minimal (swapchain only) ---\n");
    {
        float prio = 1.0f;
        VkDeviceQueueCreateInfo qci = {};
        qci.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
        qci.queueFamilyIndex = graphicsQf;
        qci.queueCount = 1;
        qci.pQueuePriorities = &prio;

        VkDeviceCreateInfo dci = {};
        dci.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
        dci.queueCreateInfoCount = 1;
        dci.pQueueCreateInfos = &qci;
        const char* minimal[] = { VK_KHR_SWAPCHAIN_EXTENSION_NAME };
        dci.enabledExtensionCount = 1;
        dci.ppEnabledExtensionNames = minimal;

        VkDevice dev = VK_NULL_HANDLE;
        r = vkCreateDevice(phys, &dci, nullptr, &dev);
        Log("Result: %d (%s)\n", r, r == VK_SUCCESS ? "SUCCESS" : "FAILED");
        if (dev) vkDestroyDevice(dev, nullptr);
    }

    // 10. EXPERIMENT 5: Check if enumeration reports an ext that's NOT actually
    //     creatable. Compare enumerate vs create for each ext.
    Log("\n--- EXPERIMENT 5: Enumerate vs Create discrepancy ---\n");
    Log("Checking if any extension is reported as supported but fails to create...\n");
    for (auto& name : allExtNames) {
        float prio = 1.0f;
        VkDeviceQueueCreateInfo qci = {};
        qci.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
        qci.queueFamilyIndex = graphicsQf;
        qci.queueCount = 1;
        qci.pQueuePriorities = &prio;

        VkDeviceCreateInfo dci = {};
        dci.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
        dci.queueCreateInfoCount = 1;
        dci.pQueueCreateInfos = &qci;
        const char* extName = name.c_str();
        dci.enabledExtensionCount = 1;
        dci.ppEnabledExtensionNames = &extName;

        VkDevice dev = VK_NULL_HANDLE;
        r = vkCreateDevice(phys, &dci, nullptr, &dev);
        if (dev) vkDestroyDevice(dev, nullptr);
        if (r != VK_SUCCESS) {
            Log("  DISCREPANCY: %s reported supported but create fails: %d\n", extName, r);
        }
    }
    Log("(no discrepancies found = all individual extensions create OK)\n");

    vkDestroyInstance(inst, nullptr);
    Log("\n=== Probe complete ===\n");
    if (g_log && g_log != stdout) fclose(g_log);
    return 0;
}
