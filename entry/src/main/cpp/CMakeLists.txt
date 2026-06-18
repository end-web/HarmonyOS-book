cmake_minimum_required(VERSION 3.5.0)
project(jsvmengine)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})

include_directories(${NATIVERENDER_ROOT_PATH})

add_library(jsvmengine SHARED napi_init.cpp)

# libace_napi.z.so: NAPI; libjsvm.so: @ohos.JSVM C-API; libhilog_ndk.z.so: 日志
# libnet_http.so: 阶段2 同步 HTTP（net_http C-API）
target_link_libraries(jsvmengine PUBLIC
    libace_napi.z.so
    libjsvm.so
    libhilog_ndk.z.so
    libnet_http.so
)
