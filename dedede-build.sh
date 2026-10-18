#!/usr/bin/env bash
# HCAM V2 PTE independent build. Run in a checkout of qilimary/Dedede-App.
# Optional --prepare-only generates the Android project without invoking Gradle.
set -euo pipefail
# ====================== Android 版本构建开关 ======================
# 【只改下一行】normal = 仅普通版（原图标+蓝色）
#               lan    = 仅兰特供版（lan.png+浅粉色）
#               both   = 同时构建两版（默认；建议本次使用）
# 以后新增或修改纠错功能，继续只维护本 dedede-build.sh。
BUILD_MODE=both
# ===============================================================
case "$BUILD_MODE" in
  normal|lan|both) ;;
  *) echo "错误：BUILD_MODE 只能填 normal、lan 或 both" >&2; exit 2 ;;
esac
MODEL_ID='1mBXuaUNVLh_vHNMRkgcLL4JlMIb-K9Qw'
MODEL_SHA='15b431068a31ff6c9483ca8df5e0d095c6dbdb0b53f80ea9dd98d9d7d9361b6a'
TOKENIZER_ID='1CEryzzuhemAB0oAQpy-vshA2XP7nOqwQ'
TOKENIZER_SHA='bed4387895500314ffba9608340c56069ca6df8635029535b9becdef8ce7ddf0'
CACHE='.model-cache-pte'
mkdir -p "$CACHE"
if ! echo "$MODEL_SHA  $CACHE/model.bin" | sha256sum -c --status 2>/dev/null; then
  gdown "$MODEL_ID" --no-cookies -O "$CACHE/model.bin"
fi
if ! echo "$TOKENIZER_SHA  $CACHE/tokenizer.json" | sha256sum -c --status 2>/dev/null; then
  gdown "$TOKENIZER_ID" --no-cookies -O "$CACHE/tokenizer.json"
fi
echo "$MODEL_SHA  $CACHE/model.bin" | sha256sum -c
echo "$TOKENIZER_SHA  $CACHE/tokenizer.json" | sha256sum -c
test "$(stat -c%s "$CACHE/model.bin")" -eq 122917632
test "$(stat -c%s "$CACHE/tokenizer.json")" -eq 327784
cp "$CACHE/model.bin" hcam_model.bin
cp "$CACHE/tokenizer.json" hcam_tokenizer.json
test -s '错别字.txt'
test -s app_icon.png
mkdir -p ".ci"
cat > ".ci/requirements-build.txt" <<'DEDEDE_SOURCE_EOF'
gdown==5.2.0
pycryptodome==3.20.0
DEDEDE_SOURCE_EOF

mkdir -p "app"
cat > "app/build.gradle" <<'DEDEDE_SOURCE_EOF'
apply plugin: 'com.android.application'
android {
    namespace 'com.app.dedede'
    compileSdk 36
    ndkVersion "27.0.12077973"
    defaultConfig {
        applicationId "com.app.dededi.pte"
        minSdk 24
        targetSdk 36
        versionCode 39
        versionName "4.1.5-PTE"
        ndk { abiFilters "arm64-v8a" }
        externalNativeBuild { cmake { cppFlags ""; arguments "-DANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES=ON" } }
    }
    buildTypes {
        release {
            minifyEnabled true
            shrinkResources true
            proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'
            signingConfig signingConfigs.debug
        }
    }
    externalNativeBuild { cmake { path "src/main/cpp/CMakeLists.txt"; version "3.22.1" } }
    compileOptions {
        sourceCompatibility JavaVersion.VERSION_11
        targetCompatibility JavaVersion.VERSION_11
    }
    aaptOptions { noCompress 'dat' }
}
dependencies {
    implementation 'androidx.appcompat:appcompat:1.6.1'
    implementation 'org.pytorch:executorch-android:1.5.1'
    implementation 'androidx.drawerlayout:drawerlayout:1.2.0'
    implementation 'com.google.mlkit:text-recognition-chinese:16.0.1'
}
DEDEDE_SOURCE_EOF

mkdir -p "app"
cat > "app/proguard-rules.pro" <<'DEDEDE_SOURCE_EOF'
-keep class org.pytorch.** { *; }
-keep class com.facebook.jni.** { *; }
-keepclasseswithmembers class * { native <methods>; }
-keep class com.app.dedede.NativeSecurity { *; }

# 仅保留 ML Kit OCR 所需的反射/原生入口。
-keep class com.google.mlkit.vision.text.** { *; }
-keep class com.google.mlkit.vision.common.** { *; }
-keep class com.google.mlkit.common.sdkinternal.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_text_common.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_text_bundled_common.** { *; }
-keepclasseswithmembernames class com.google.mlkit.** { native <methods>; }
-keepclasseswithmembernames class com.google.android.gms.internal.mlkit_vision_text_** { native <methods>; }
-dontwarn com.google.mlkit.**
-dontwarn com.google.android.gms.internal.mlkit_vision_text_**
-dontwarn org.pytorch.**

-keep class com.app.dedede.ModelEngine$BoolTensor { *; }
DEDEDE_SOURCE_EOF

mkdir -p "app/src/main"
cat > "app/src/main/AndroidManifest.xml" <<'DEDEDE_SOURCE_EOF'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.SYSTEM_ALERT_WINDOW"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_SPECIAL_USE"/>
    <application android:name=".DededeApp" android:allowBackup="false" android:icon="@mipmap/ic_launcher" android:roundIcon="@mipmap/ic_launcher" android:label="纠错 Pro" android:theme="@style/Theme.Dedede" android:enableOnBackInvokedCallback="false">
        <activity android:name=".MainActivity" android:exported="true" android:launchMode="singleTask" android:windowSoftInputMode="adjustResize">
            <intent-filter><action android:name="android.intent.action.MAIN"/><category android:name="android.intent.category.LAUNCHER"/></intent-filter>
            <intent-filter><action android:name="android.intent.action.SEND"/><category android:name="android.intent.category.DEFAULT"/><data android:mimeType="text/plain"/></intent-filter>
            <intent-filter><action android:name="android.intent.action.SEND"/><category android:name="android.intent.category.DEFAULT"/><data android:mimeType="image/*"/></intent-filter>
        </activity>
        <activity android:name=".FilePickerActivity" android:theme="@android:style/Theme.Translucent.NoTitleBar" android:taskAffinity="${applicationId}.filepicker" android:excludeFromRecents="true"/>
        <activity android:name=".SymbolCleanActivity" android:theme="@android:style/Theme.Translucent.NoTitleBar" android:taskAffinity="${applicationId}.symbolclean" android:excludeFromRecents="true"/>
        <service android:name=".FloatingService" android:exported="false" android:foregroundServiceType="specialUse">
            <property android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE" android:value="User-invoked persistent floating text correction overlay"/>
        </service>
    </application>
</manifest>
DEDEDE_SOURCE_EOF

mkdir -p "app/src/main/cpp"
cat > "app/src/main/cpp/CMakeLists.txt" <<'DEDEDE_SOURCE_EOF'
cmake_minimum_required(VERSION 3.10.2)
project("dedede")
add_library(dedede SHARED native-lib.cpp key-part-a.cpp key-part-b.cpp)
target_compile_features(dedede PRIVATE cxx_std_11)
target_compile_options(dedede PRIVATE -O2 -fvisibility=hidden -ffunction-sections -fdata-sections)
find_library(log-lib log)
target_link_libraries(dedede ${log-lib} android -Wl,--gc-sections)
DEDEDE_SOURCE_EOF

mkdir -p "app/src/main/cpp"
cat > "app/src/main/cpp/native-lib.cpp" <<'DEDEDE_SOURCE_EOF'
#include <jni.h>
#include <algorithm>
#include <array>
#include <cctype>
#include <cstdio>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

extern "C" void dededeFillKeyPartA(uint8_t out[32]);
extern "C" void dededeFillKeyPartB(uint8_t out[32]);

namespace {
constexpr char DOMAIN[] = "DEDEDE-ASSET-V2\0";

void wipe(void* pointer, size_t length) {
    volatile unsigned char* bytes = static_cast<volatile unsigned char*>(pointer);
    while (length--) *bytes++ = 0;
}

bool tracerAttached() {
    FILE* file = fopen("/proc/self/status", "r");
    if (!file) return false;
    char line[256];
    bool attached = false;
    while (fgets(line, sizeof(line), file)) {
        if (strncmp(line, "TracerPid:", 10) == 0) {
            const char* value = line + 10;
            while (*value && std::isspace(static_cast<unsigned char>(*value))) ++value;
            attached = atoi(value) != 0;
            break;
        }
    }
    fclose(file);
    return attached;
}

bool suspiciousMappings() {
    FILE* file = fopen("/proc/self/maps", "r");
    if (!file) return false;
    char line[1024];
    bool suspicious = false;
    while (fgets(line, sizeof(line), file)) {
        std::string value(line);
        std::transform(value.begin(), value.end(), value.begin(), [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
        if (value.find("frida") != std::string::npos || value.find("gum-js-loop") != std::string::npos || value.find("libgadget") != std::string::npos) {
            suspicious = true;
            break;
        }
    }
    fclose(file);
    return suspicious;
}

bool sha256(JNIEnv* env, const std::vector<uint8_t>& input, std::array<uint8_t, 32>& output) {
    jclass cls = env->FindClass("java/security/MessageDigest");
    if (!cls) return false;
    jmethodID getInstance = env->GetStaticMethodID(cls, "getInstance", "(Ljava/lang/String;)Ljava/security/MessageDigest;");
    jmethodID digest = env->GetMethodID(cls, "digest", "([B)[B");
    if (!getInstance || !digest) { env->DeleteLocalRef(cls); return false; }
    jstring algorithm = env->NewStringUTF("SHA-256");
    jobject md = env->CallStaticObjectMethod(cls, getInstance, algorithm);
    env->DeleteLocalRef(algorithm);
    if (env->ExceptionCheck() || !md) { env->ExceptionClear(); env->DeleteLocalRef(cls); return false; }
    jbyteArray bytes = env->NewByteArray(static_cast<jsize>(input.size()));
    if (!bytes) { env->DeleteLocalRef(md); env->DeleteLocalRef(cls); return false; }
    if (!input.empty()) env->SetByteArrayRegion(bytes, 0, static_cast<jsize>(input.size()), reinterpret_cast<const jbyte*>(input.data()));
    auto result = static_cast<jbyteArray>(env->CallObjectMethod(md, digest, bytes));
    bool ok = !env->ExceptionCheck() && result && env->GetArrayLength(result) == 32;
    if (env->ExceptionCheck()) env->ExceptionClear();
    if (ok) env->GetByteArrayRegion(result, 0, 32, reinterpret_cast<jbyte*>(output.data()));
    if (result) env->DeleteLocalRef(result);
    env->DeleteLocalRef(bytes); env->DeleteLocalRef(md); env->DeleteLocalRef(cls);
    return ok;
}

bool hmacSha256(JNIEnv* env, const uint8_t key[32], const std::vector<uint8_t>& message, std::array<uint8_t, 32>& output) {
    std::array<uint8_t, 64> ipad{}, opad{};
    for (size_t i = 0; i < 64; ++i) {
        uint8_t value = i < 32 ? key[i] : 0;
        ipad[i] = static_cast<uint8_t>(value ^ 0x36U);
        opad[i] = static_cast<uint8_t>(value ^ 0x5CU);
    }
    std::vector<uint8_t> inner; inner.reserve(64 + message.size()); inner.insert(inner.end(), ipad.begin(), ipad.end()); inner.insert(inner.end(), message.begin(), message.end());
    std::array<uint8_t, 32> innerHash{};
    if (!sha256(env, inner, innerHash)) return false;
    std::vector<uint8_t> outer; outer.reserve(96); outer.insert(outer.end(), opad.begin(), opad.end()); outer.insert(outer.end(), innerHash.begin(), innerHash.end());
    bool ok = sha256(env, outer, output);
    wipe(inner.data(), inner.size()); wipe(outer.data(), outer.size()); wipe(innerHash.data(), innerHash.size()); wipe(ipad.data(), ipad.size()); wipe(opad.data(), opad.size());
    return ok;
}
}

extern "C" JNIEXPORT jbyteArray JNICALL
Java_com_app_dedede_NativeSecurity_deriveAssetKeyNative(JNIEnv* env, jclass, jbyteArray javaPart, jbyteArray buildToken, jbyteArray salt, jstring assetName) {
    if (!javaPart || !buildToken || !salt || !assetName || (tracerAttached() && suspiciousMappings())) return nullptr;
    if (env->GetArrayLength(javaPart) != 32 || env->GetArrayLength(buildToken) != 16 || env->GetArrayLength(salt) != 16) return nullptr;
    std::array<uint8_t, 32> partA{}, partB{}, partC{}, master{}, derived{};
    std::array<uint8_t, 16> token{}, saltBytes{};
    dededeFillKeyPartA(partA.data()); dededeFillKeyPartB(partB.data());
    env->GetByteArrayRegion(javaPart, 0, 32, reinterpret_cast<jbyte*>(partC.data()));
    env->GetByteArrayRegion(buildToken, 0, 16, reinterpret_cast<jbyte*>(token.data()));
    env->GetByteArrayRegion(salt, 0, 16, reinterpret_cast<jbyte*>(saltBytes.data()));
    for (size_t i = 0; i < 32; ++i) master[i] = static_cast<uint8_t>(partA[i] ^ partB[i] ^ partC[i]);
    const char* name = env->GetStringUTFChars(assetName, nullptr);
    if (!name) return nullptr;
    std::vector<uint8_t> message;
    message.insert(message.end(), DOMAIN, DOMAIN + sizeof(DOMAIN) - 1);
    message.insert(message.end(), token.begin(), token.end());
    message.insert(message.end(), saltBytes.begin(), saltBytes.end());
    message.insert(message.end(), name, name + strlen(name));
    env->ReleaseStringUTFChars(assetName, name);
    bool ok = hmacSha256(env, master.data(), message, derived);
    jbyteArray result = nullptr;
    if (ok) {
        result = env->NewByteArray(32);
        if (result) env->SetByteArrayRegion(result, 0, 32, reinterpret_cast<const jbyte*>(derived.data()));
    }
    wipe(partA.data(), partA.size()); wipe(partB.data(), partB.size()); wipe(partC.data(), partC.size()); wipe(master.data(), master.size()); wipe(derived.data(), derived.size()); wipe(token.data(), token.size()); wipe(saltBytes.data(), saltBytes.size()); wipe(message.data(), message.size());
    return result;
}
DEDEDE_SOURCE_EOF

mkdir -p "app/src/main/java/com/app/dedede"
cat > "app/src/main/java/com/app/dedede/AppExecutors.java" <<'DEDEDE_SOURCE_EOF'
package com.app.dedede;
import android.os.Handler;
import android.os.Looper;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.LinkedBlockingQueue;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.ThreadFactory;
import java.util.concurrent.atomic.AtomicInteger;

public final class AppExecutors {
    public static final Handler MAIN = new Handler(Looper.getMainLooper());
    public static final Object HISTORY_LOCK = new Object();
    public static final ExecutorService IO = pool(2, "dedede-io");
    public static final ExecutorService HISTORY = pool(1, "dedede-history");
    public static final ExecutorService INFERENCE = pool(1, "dedede-inference");
    private AppExecutors() {}
    private static ExecutorService pool(int size, String name) {
        ThreadPoolExecutor pool = new ThreadPoolExecutor(size, size, 30, TimeUnit.SECONDS, new LinkedBlockingQueue<>(), namedFactory(name));
        pool.allowCoreThreadTimeOut(true); return pool;
    }
    private static ThreadFactory namedFactory(String prefix) {
        AtomicInteger counter = new AtomicInteger(1);
        return runnable -> {
            Thread thread = new Thread(runnable, prefix + "-" + counter.getAndIncrement());
            thread.setPriority(Thread.NORM_PRIORITY - 1);
            return thread;
        };
    }
}
DEDEDE_SOURCE_EOF

mkdir -p "app/src/main/java/com/app/dedede"
cat > "app/src/main/java/com/app/dedede/Proofreader.java" <<'DEDEDE_SOURCE_EOF'
package com.app.dedede;

import java.io.*;
import java.util.*;
import java.util.function.BooleanSupplier;
import java.util.regex.Pattern;

/** Exact matches are collected globally before approximate matching. No segmentation/model dependency. */
public final class Proofreader {
    // sync_android.py exports these policy strings to Windows. Maintain the word lists here only.
    public static final String POLICY_VERSION = "3";
    public static final String LEFT = "我|你|他|她|它|您|咱|我们|你们|他们|她们|它们|咱们|您们|大家|真是|真|太|很|十分|非常|格外|特别|确实|实在|简直|可谓|堪称|令人|让人|使人|感到|觉得|显得|变得|表现得|不禁|仍然|依然|已经|总是|一直|竟然|居然|于是|因此|所以|可是|但是|却|也|都|又";
    public static final String RIGHT = "的|地|得|了|着|过|般|似的|一样|一般|啊|呀|吧|呢|吗|嘛|想|要|去|来|起来|下去";
    public static final String DUP_LEFT = "今天|昨天|明天|刚才|现在|后来|于是|因此|所以|其实|不过|可是|但是|而且|然后|最近|当时|这次|这时|随后|目前|本来|原来|因为|如果|假如|既然|虽然|只要";
    public static final String DUP_RIGHT = "今天|昨天|明天|刚才|现在|已经|正在|刚刚|刚|曾经|从来|一直|总是|终于|马上|即将|明明|确实|真的|真|都|也|又|还|就|才|只|正|先|再|不|没|别|很|太|更|最|是|有|要|会|能|想|去|来|说|看|听|吃|喝|做|走|跑|买|把|被|在|对|向|给|让|喜欢|觉得|认为|知道|希望|准备|打算|决定|需要|应该|必须|可以|愿意|敢|将|已|不曾|未曾";
    public static final String PRONOUNS = "我你他她它您咱";
    public static final String REPEATED_WORDS = "我们|你们|他们|她们|它们|咱们|您们|已经|正在|因为|所以|但是|而且|如果|虽然|于是|以及|还是|就是|是否|可以|能够|需要|必须|应该";
    public static final String FUNCTION = "不无未非莫勿别难免没休的地得了着过在是也又还很和与而就都才要会能可给让被把将一二三四五六七八九十百千万亿零两其此彼之于以为乃则者所乎焉耶哉矣兮些每各任某该本这那我你他她它您咱们";
    public static final String NAMING = "笔名|网名|姓名|名字|昵称|称呼|书名|篇名|标题|词语|词组|字样|写法|变量名|函数名|角色名|代号|署名|个词|个字";
    public static final String NUMERALS = "零〇一二两三四五六七八九十百千万亿兆几数半0123456789";
    public static final String QUANTITY_UNITS = "个只条头匹辆部台口尾座把本名位双对件张枚颗棵根支枝朵艘架间所套份册块片段次遍趟场回岁年月日天时分秒斤克吨米升元角毛";
    private static final String[] LEFT_WORDS=LEFT.split("\\|"),RIGHT_WORDS=RIGHT.split("\\|"),
        DUP_LEFT_WORDS=DUP_LEFT.split("\\|"),DUP_RIGHT_WORDS=DUP_RIGHT.split("\\|"),
        NAMES=NAMING.split("\\|"),REPEATS=REPEATED_WORDS.split("\\|");
    private static final Pattern CUE=Pattern.compile(".*(?:成语|四字词语|四字词|熟语)(?:[：: 　]|是|为|叫|叫作|写成|写作|应该是|应为|应写作){0,4}");
    public static final class Edit {
        public final int start,end;
        public final String source,replacement,explanation;
        public final boolean idiom;
        Edit(int start,String source,String replacement,String explanation){this(start,source,replacement,explanation,false);}
        Edit(int start,String source,String replacement,String explanation,boolean idiom){this.start=start;this.end=start+source.length();this.source=source;this.replacement=replacement;this.explanation=explanation;this.idiom=idiom;}
    }
    private final Set<String> words=new HashSet<>();
    private final Map<String,String> substitutions=new HashMap<>(),missing=new HashMap<>();
    private final Set<Integer> fuzzyLengths=new HashSet<>();
    /** Lookup-only probe: never inserted into a map; compares directly with stored pattern strings. */
    private static final class SubstitutionProbe {
        String source;int wildcard;
        @Override public int hashCode(){int h=0;for(int i=0;i<source.length();i++)h=31*h+(i==wildcard?'*':source.charAt(i));return h;}
        @Override public boolean equals(Object other){
            if(other==this)return true;if(!(other instanceof String))return false;String key=(String)other;
            if(key.length()!=source.length())return false;
            for(int i=0;i<source.length();i++)if(key.charAt(i)!=(i==wildcard?'*':source.charAt(i)))return false;return true;
        }
    }
    // Compact trie: integer/character arrays, no substring allocation during exact scanning.
    private final int[] roots,first,edges;
    private final char[] labels;
    private final boolean[] terminals;
    public Proofreader(Reader input)throws IOException {

        if(input!=null)try(BufferedReader reader=new BufferedReader(input)){
            for(String raw;(raw=reader.readLine())!=null;){
                String word=raw.replace("\ufeff","").trim();
                if(word.length()<2||word.length()>64||!allHan(word)||!words.add(word))continue;

                if(word.length()<4||word.length()>8||word.codePointCount(0,word.length())!=word.length())continue;
                fuzzyLengths.add(word.length());
                for(int i=0;i<word.length();i++)unique(substitutions,word.substring(0,i)+"*"+word.substring(i+1),word);
                for(int i=1;i+1<word.length();i++)unique(missing,word.substring(0,i)+word.substring(i+1),word);
            }
        }
        String[] sorted=words.toArray(new String[0]);Arrays.sort(sorted);int capacity=1,max=0;
        for(String word:sorted){capacity+=word.length();max=Math.max(max,word.length());}
        int[] parents=new int[capacity],counts=new int[capacity],path=new int[max+1];char[] chars=new char[capacity];boolean[] ends=new boolean[capacity];
        String previous="";int size=1;
        for(String word:sorted){int common=0;while(common<previous.length()&&common<word.length()&&previous.charAt(common)==word.charAt(common))common++;
            for(int i=common;i<word.length();i++){int node=size++,parent=path[i];parents[node]=parent;counts[parent]++;chars[node]=word.charAt(i);path[i+1]=node;}
            ends[path[word.length()]]=true;previous=word;
        }
        first=new int[size+1];edges=new int[size-1];roots=new int[65536];labels=Arrays.copyOf(chars,size);terminals=Arrays.copyOf(ends,size);
        for(int i=0;i<size;i++)first[i+1]=first[i]+counts[i];int[] next=first.clone();
        for(int node=1;node<size;node++){edges[next[parents[node]]++]=node;if(parents[node]==0)roots[chars[node]]=node;}
    }
    private int child(int node,char c){int low=first[node],high=first[node+1]-1;while(low<=high){int mid=(low+high)>>>1,n=edges[mid];if(labels[n]==c)return n;if(labels[n]<c)low=mid+1;else high=mid-1;}return 0;}
    private static void unique(Map<String,String> index,String key,String word){String old=index.get(key);index.put(key,old==null||old.equals(word)?word:"");}
    public int size(){return words.size();}
    private static boolean han(char c){return c>='\u3400'&&c<='\u9fff'||c>='\uf900'&&c<='\ufaff';}
    private static boolean hanCodePoint(int cp){return cp>=0x3400&&cp<=0x9fff||cp>=0xf900&&cp<=0xfaff||cp>=0x20000&&cp<=0x2fa1f||cp>=0x30000&&cp<=0x323af;}
    private static boolean allHan(String s){for(int i=0;i<s.length();){int cp=s.codePointAt(i);if(!hanCodePoint(cp))return false;i+=Character.charCount(cp);}return true;}
    public boolean[] exactPositions(String text){return exactPositions(text,()->false);}
    public boolean[] exactPositions(String text,BooleanSupplier cancelled){
        boolean[] mask=new boolean[text.length()];
        for(int p=0;p<text.length();p++){
            if((p&255)==0&&cancelled.getAsBoolean())return null;
            int node=roots[text.charAt(p)];if(node==0)continue;
            for(int end=p+1;node!=0;end++){
                if(terminals[node])Arrays.fill(mask,p,end,true);
                if(end==text.length())break;node=child(node,text.charAt(end));
            }
        }
        return mask;
    }
    public void markExact(String text,boolean[] mask){boolean[] found=exactPositions(text);for(int i=0;i<found.length;i++)mask[i]|=found[i];}
    /** Protect quotations, titles and inline code before sentence splitting. */
    public static boolean[] literalPositions(String text){
        boolean[] mask=new boolean[text.length()];ArrayList<Character> closes=new ArrayList<>();int begin=-1;
        String opens="《〈“‘「『\"'`",ends="》〉”’」』\"'`";
        for(int i=0;i<text.length();i++){
            char c=text.charAt(i);
            if(!closes.isEmpty()&&c==closes.get(closes.size()-1)){
                closes.remove(closes.size()-1);if(closes.isEmpty()){Arrays.fill(mask,begin,i+1,true);begin=-1;}continue;
            }
            int key=opens.indexOf(c);
            if(c=='\''&&i>0&&i+1<text.length()&&asciiLetter(text.charAt(i-1))&&asciiLetter(text.charAt(i+1)))key=-1;
            if(key>=0){if(closes.isEmpty())begin=i;closes.add(ends.charAt(key));}

        }
        if(begin>=0){int end=text.indexOf('\n',begin);Arrays.fill(mask,begin,end<0?text.length():end,true);}return mask;
    }
    private static boolean asciiLetter(char c){return c>='a'&&c<='z'||c>='A'&&c<='Z';}
    private static boolean any(boolean[] mask,int start,int end){for(int i=start;i<end;i++)if(mask[i])return true;return false;}
    private static boolean suffix(String text,int end,String[] choices){for(String s:choices)if(end>=s.length()&&text.regionMatches(end-s.length(),s,0,s.length()))return true;return false;}
    private static boolean prefix(String text,int start,String[] choices){for(String s:choices)if(text.startsWith(s,start))return true;return false;}
    private static boolean left(String text,int start,String[] choices){return start==0||(!Character.isLetterOrDigit(text.codePointBefore(start))&&text.charAt(start-1)!='_')||suffix(text,start,choices);}
    private static boolean right(String text,int end){return end==text.length()||(!Character.isLetterOrDigit(text.codePointAt(end))&&text.charAt(end)!='_')||prefix(text,end,RIGHT_WORDS);}
    private static boolean cue(String text,int start){if(start==0||"：: 　是为叫作语词".indexOf(text.charAt(start-1))<0)return false;int begin=start;while(begin>0&&start-begin<18&&"。！？!?；;\n".indexOf(text.charAt(begin-1))<0)begin--;return CUE.matcher(text.substring(begin,start)).matches();}
    private static boolean namedUse(String text,int end){
        if(!text.startsWith("是",end)&&!text.startsWith("为",end)&&!text.startsWith("作为",end)&&!text.startsWith("用作",end))return false;
        int stop=Math.min(text.length(),end+18);for(int i=end;i<stop;i++){if("。！？!?；;，,\n".indexOf(text.charAt(i))>=0)break;if(prefix(text,i,NAMES))return true;}return false;
    }
    private static int contentCount(String source){int count=0;for(int i=0;i<source.length();i++)if(FUNCTION.indexOf(source.charAt(i))<0)count++;return count;}
    private static int removedAt(String longer,String shorter){int i=0;while(i<shorter.length()&&longer.charAt(i)==shorter.charAt(i))i++;return i;}
    private static boolean changesQuantity(String text,int start,String source,String target){
        int diff=0;while(diff<source.length()&&source.charAt(diff)==target.charAt(diff))diff++;
        int at=start+diff;
        return diff<source.length()&&at>0&&at+1<text.length()&&QUANTITY_UNITS.indexOf(source.charAt(diff))>=0&&NUMERALS.indexOf(text.charAt(at-1))>=0&&han(text.charAt(at+1));
    }
    // A function-word expansion may be intentional, e.g. 名不副其实. Do not repair its partial window.
    private static boolean functionExpansion(String text,int start,String source,String target){
        int size=source.length()+1;
        for(int begin=Math.max(0,start-1);begin<=start;begin++){
            if(begin+size>text.length())continue;
            for(int skip=1;skip+1<size;skip++){
                if(FUNCTION.indexOf(text.charAt(begin+skip))<0)continue;
                boolean same=true;for(int i=0;i<target.length();i++)if(target.charAt(i)!=text.charAt(begin+i+(i>=skip?1:0))){same=false;break;}
                if(same)return true;
            }
        }
        return false;
    }
    private void candidates(String text,int start,String source,boolean[] exact,Map<String,String> targets,boolean explicit,boolean structural,SubstitutionProbe probe){
        int size=source.length(),end=start+size;
        boolean protectedSpan=any(exact,start,end);
        if(!protectedSpan&&fuzzyLengths.contains(size)&&!namedUse(text,end)){
            String candidate=null;boolean ambiguous=false;
            probe.source=source;
            for(int i=0;i<size;i++){
                probe.wildcard=i;String word=substitutions.get(probe);
                if(word==null)continue;
                if(word.isEmpty()||candidate!=null&&!candidate.equals(word)){ambiguous=true;break;}
                candidate=word;
            }
            if(!ambiguous&&candidate!=null&&!functionExpansion(text,start,source,candidate)&&!changesQuantity(text,start,source,candidate))targets.put(candidate,"");
        }
        // Keep insertion/deletion and transposition checks under their existing context limits.
        if(!structural)return;
        if(!protectedSpan&&explicit&&fuzzyLengths.contains(size)){
            Set<String> swaps=new HashSet<>();
            for(int i=0;i+1<size;i++){if(source.charAt(i)==source.charAt(i+1))continue;String swapped=source.substring(0,i)+source.charAt(i+1)+source.charAt(i)+source.substring(i+2);if(words.contains(swapped))swaps.add(swapped);}
            if(swaps.size()==1)targets.put(swaps.iterator().next(),"");
        }
        if(size>=5){Set<String> extra=new HashSet<>();
            for(int i=0;i<size;i++){
                int runEnd=i+1;while(runEnd<size&&source.charAt(runEnd)==source.charAt(i))runEnd++;
                for(int count=1;count<=Math.max(1,runEnd-i-(i>0&&source.charAt(i)==source.charAt(i-1)?0:1));count++){
                    if(!fuzzyLengths.contains(size-count)||any(exact,start+i,start+i+count))continue;
                    String word=source.substring(0,i)+source.substring(i+count);if(!words.contains(word))continue;
                    boolean repeated=i>0&&source.charAt(i)==source.charAt(i-1)||i+count<size&&source.charAt(i)==source.charAt(i+count);
                    if(protectedSpan){if(!repeated||!(source.startsWith(word)||source.endsWith(word)))continue;}
                    else if(!repeated&&(i==0||i==size-1||FUNCTION.indexOf(source.charAt(i))>=0))continue;
                    extra.add(word);
                }
            }
            if(extra.size()==1)targets.put(extra.iterator().next(),"");
        }
        if(!protectedSpan&&explicit&&fuzzyLengths.contains(size+1)&&contentCount(source)>=2){
            String word=missing.get(source);if(word!=null&&!word.isEmpty()){int insertion=removedAt(word,source);if(FUNCTION.indexOf(word.charAt(insertion))<0)targets.put(word,"");}
        }
    }
    /** Keep mixed identifiers intact; explicit custom mappings still take precedence. */
    public static boolean touchesIdentifier(String text,int start,int end){
        return start>0&&identifierCharacter(text.codePointBefore(start))||end<text.length()&&identifierCharacter(text.codePointAt(end));
    }
    private static boolean identifierCharacter(int cp){return cp=='_'||!hanCodePoint(cp)&&Character.isLetterOrDigit(cp);}
    /** A built-in permutation must not reorder the seam of a legitimate ABAB/ABCABC repetition. */
    public static boolean crossesRepetition(String text,int start,String source,String replacement){
        if(source.length()<2||source.length()>16||source.length()!=replacement.length()||source.equals(replacement))return false;
        char[] a=source.toCharArray(),b=replacement.toCharArray();Arrays.sort(a);Arrays.sort(b);if(!Arrays.equals(a,b))return false;
        int end=start+source.length();
        for(int width=2;width<=8;width++)for(int middle=start+1;middle<end;middle++){
            int begin=middle-width,stop=middle+width;
            if(begin>=0&&stop<=text.length()&&begin<=start&&end<=stop&&text.regionMatches(begin,text,middle,width))return true;
        }
        return false;
    }
    public static boolean altersExact(boolean[] mask,int start,String source,String replacement){
        int prefix=0,suffix=0;
        while(prefix<source.length()&&prefix<replacement.length()&&source.charAt(prefix)==replacement.charAt(prefix))prefix++;
        while(suffix<source.length()-prefix&&suffix<replacement.length()-prefix&&source.charAt(source.length()-1-suffix)==replacement.charAt(replacement.length()-1-suffix))suffix++;
        int begin=start+prefix,end=start+source.length()-suffix;
        return any(mask,begin,end)||begin==end&&prefix<replacement.length()-suffix&&begin>0&&begin<mask.length&&mask[begin-1]&&mask[begin];
    }
    public Edit[] collect(String text,boolean[] custom,boolean[] exact,boolean[] literals,boolean idioms,boolean repetition){return collect(text,custom,exact,literals,idioms,repetition,()->false);}
    public Edit[] collect(String text,boolean[] custom,boolean[] exact,boolean[] literals,boolean idioms,boolean repetition,BooleanSupplier cancelled){
        ArrayList<Edit> pending=new ArrayList<>();Map<String,String> targets=new HashMap<>();SubstitutionProbe probe=new SubstitutionProbe();
        for(int p=0;p<text.length();p++){
            if((p&255)==0&&cancelled.getAsBoolean())return null;
            if(!han(text.charAt(p))||custom[p]||literals[p])continue;
            boolean checkIdioms=idioms&&!fuzzyLengths.isEmpty(),explicit=checkIdioms&&cue(text,p);
            if(checkIdioms){boolean structuralLeft=explicit||left(text,p,LEFT_WORDS);int stop=p;while(stop<text.length()&&stop<p+9&&han(text.charAt(stop)))stop++;
            for(int size=3;p+size<=stop;size++){
                boolean structural=structuralLeft&&right(text,p+size);
                if((!fuzzyLengths.contains(size)||any(exact,p,p+size))&&!structural||touchesIdentifier(text,p,p+size))continue;
                if(any(custom,p,p+size)||any(literals,p,p+size))continue;
                String source=text.substring(p,p+size);if(words.contains(source))continue;
                targets.clear();candidates(text,p,source,exact,targets,explicit,structural,probe);
                if(targets.size()==1){String replacement=targets.keySet().iterator().next();pending.add(new Edit(p,source,replacement,targets.get(replacement),true));}
            }}
            if(!repetition)continue;
            char c=text.charAt(p);int end=p+1;
            if(PRONOUNS.indexOf(c)>=0&&(p==0||text.charAt(p-1)!=c))while(end<text.length()&&text.charAt(end)==c)end++;
            if(PRONOUNS.indexOf(c)>=0&&end-p>=2&&(p==0||text.charAt(p-1)!=c)&&left(text,p,DUP_LEFT_WORDS)&&prefix(text,end,DUP_RIGHT_WORDS)&&!namedUse(text,end)&&!any(custom,p,end)&&!any(exact,p,end)&&!any(literals,p,end))pending.add(new Edit(p,text.substring(p,end),String.valueOf(c),""));
            for(String word:REPEATS){
                if(c!=word.charAt(0)||p>=word.length()&&text.regionMatches(p-word.length(),word,0,word.length()))continue;int stop=p+word.length()*2;
                if(stop>text.length()||!text.startsWith(word+word,p)||!(left(text,p,DUP_LEFT_WORDS)||suffix(text,p,LEFT_WORDS))||stop==text.length()||!han(text.charAt(stop)))continue;
                while(text.startsWith(word,stop))stop+=word.length();
                if(stop<text.length()&&han(text.charAt(stop))&&!namedUse(text,stop)&&!any(custom,p,stop)&&!any(exact,p,stop)&&!any(literals,p,stop))pending.add(new Edit(p,text.substring(p,stop),word,""));
            }
        }
        pending.sort((a,b)->a.start!=b.start?Integer.compare(a.start,b.start):Integer.compare(b.end,a.end));
        boolean[] conflicts=new boolean[pending.size()];
        for(int i=0;i<pending.size();i++){Edit a=pending.get(i);
            for(int j=i+1;j<pending.size()&&pending.get(j).start<a.end;j++){Edit b=pending.get(j);int end=Math.max(a.end,b.end);
                String one=a.replacement+text.substring(a.end,end),two=text.substring(a.start,b.start)+b.replacement+text.substring(b.end,end);
                if(!one.equals(two)){
                    boolean structuralA=a.source.length()!=a.replacement.length(),structuralB=b.source.length()!=b.replacement.length();
                    if(structuralA!=structuralB)conflicts[structuralA?j:i]=true;
                    else{conflicts[i]=true;conflicts[j]=true;}
                }
            }
        }
        Edit[] hits=new Edit[text.length()];int takenEnd=0;
        for(int i=0;i<pending.size();i++){Edit edit=pending.get(i);if(!conflicts[i]&&edit.start>=takenEnd){hits[edit.start]=edit;takenEnd=edit.end;}}
        return hits;
    }
}
DEDEDE_SOURCE_EOF

mkdir -p "app/src/main/java/com/app/dedede"
cat > "app/src/main/java/com/app/dedede/ProofreaderAssets.java" <<'DEDEDE_SOURCE_EOF'
package com.app.dedede;
import java.io.IOException;
import java.io.StringReader;
final class ProofreaderAssets {
    private static Proofreader instance;
    private ProofreaderAssets() {}
    static synchronized Proofreader get() throws IOException {
        if (instance != null) return instance;
        boolean present = false;
        for (String name : DededeApp.context().getAssets().list("")) if ("sys_idioms.dat".equals(name)) present = true;
        // Missing is optional. Authentication/corruption failures must still report their real error.
        instance = new Proofreader(present ? new StringReader(SecureAsset.readUtf8(DededeApp.context(), "sys_idioms.dat")) : null);
        return instance;
    }
}
DEDEDE_SOURCE_EOF

mkdir -p "app/src/main/java/com/app/dedede"
cat > "app/src/main/java/com/app/dedede/CorrectionCore.java" <<'DEDEDE_SOURCE_EOF'
package com.app.dedede;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Locale;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public final class CorrectionCore {
    private static final String[] LABELS = {"的", "地", "得", "做", "作"};
    private static final int MAX_SEQUENCE_LENGTH = 300;
    private CorrectionCore() {}

    public interface Listener {
        boolean isCancelled();
        void onProgress(int current, int total, List<List<MainActivity.TextBlock>> completed, int errorCount, long elapsedMs);
        void onError(String message, boolean needsMinimumDisplay);
    }

    public static final class Result {
        public final List<List<MainActivity.TextBlock>> blocks;
        public final String cleanText;
        public final int errorCount;
        public final long elapsedMs;
        public long modelNanos; public int modelCalls,reviewCalls;
        Result(List<List<MainActivity.TextBlock>> blocks, String cleanText, int errorCount, long elapsedMs) {
            this.blocks = blocks; this.cleanText = cleanText; this.errorCount = errorCount; this.elapsedMs = elapsedMs;
        }
    }

    private static final class GrammarHit {
        final MainActivity.GramRule rule;
        final int end;
        final String group1;
        final String group2;
        final String group3;
        final String[] gaps = new String[4];

        GrammarHit(MainActivity.GramRule rule, Matcher match, String sentence) {
            this.rule = rule;
            this.end = match.end();
            this.group1 = match.group(1);
            this.group2 = match.group(2);
            this.group3 = match.group(3);
            int at = match.start();
            for (int i = 1; i <= 3; i++) {
                int start = match.start(i);
                gaps[i - 1] = start >= at ? sentence.substring(at, start) : "";
                if (start >= at) at = match.end(i);
            }
            gaps[3] = sentence.substring(at, end);
        }
    }

    private static GrammarHit[] collectGrammarHits(String sentence, boolean fastMode, boolean[] protectedPositions, boolean[] exactPositions) {
        GrammarHit[] hits = new GrammarHit[sentence.length()];
        for (MainActivity.GramRule rule : MainActivity.gramRules) {
            if (fastMode && rule.professionalOnly) continue;
            Matcher matcher = rule.pattern.matcher(sentence).useTransparentBounds(true).useAnchoringBounds(false);
            int searchStart = 0;
            while (searchStart < sentence.length()) {
                matcher.region(searchStart, sentence.length());
                if (!matcher.find()) break;
                int matchStart = matcher.start();
                boolean protectedHit = false;
                for (int i = matchStart; i < matcher.end(); i++) if (protectedPositions[i]) { protectedHit = true; break; }
                String[] option = rule.options[0];
                String replacement = (option[0] != null ? option[0] : matcher.group(1)) + matcher.group(2)
                        + (option.length > 1 && option[1] != null ? option[1] : matcher.group(3));
                if (Proofreader.altersExact(exactPositions, matchStart, matcher.group(), replacement)) protectedHit = true;
                if (hits[matchStart] == null && !protectedHit) {
                    hits[matchStart] = new GrammarHit(rule, matcher, sentence);
                }
                searchStart = matchStart + 1;
            }
        }
        return hits;
    }

    public static Result run(String text, boolean fastMode, float temperature, float thresholdDe, float thresholdDi, float thresholdDe3, float thresholdZuo, float thresholdZuo4, Listener listener) throws Exception {
        float[] thresholds={thresholdDe,thresholdDi,thresholdDe3,thresholdZuo,thresholdZuo4};
        if(!fastMode) for(float v:thresholds) if(!Float.isFinite(v)||v<0f||v>1f) throw new IllegalArgumentException("五字阈值必须是0～1之间的数字");
        long modelNanos=0;int modelCalls=0,reviewCalls=0;
        MainActivity.ensureTypoMapLoaded(DededeApp.context());
        MainActivity.ensureRulesLoaded();
        final MainActivity.TypoIndex dictionary = MainActivity.currentTypoIndex();
        long startTime = android.os.SystemClock.elapsedRealtime();
        final Proofreader proofreader = ProofreaderAssets.get();
        final boolean[] exactAll = proofreader.exactPositions(text, () -> listener != null && listener.isCancelled());
        if (exactAll == null) return null;
        final boolean[] customAll = dictionary.protectedPositions(text);
        final Proofreader.Edit[] proofEdits = proofreader.collect(text, customAll, exactAll, Proofreader.literalPositions(text), true, true, () -> listener != null && listener.isCancelled());
        if (proofEdits == null) return null;
        final boolean[] blockedAll = customAll.clone();
        for (Proofreader.Edit edit : proofEdits) if (edit != null) Arrays.fill(blockedAll, edit.start, edit.end, true);
        int sentenceOffset = 0, skipUntil = 0;
        List<String> sentences = splitText(text);
        List<List<MainActivity.TextBlock>> allBlocks = new ArrayList<>(sentences.size());
        StringBuilder fullCleanText = new StringBuilder(text.length());
        int errorCount = 0;
        long lastProgressTime = 0;

        for (int sentenceIndex = 0; sentenceIndex < sentences.size(); sentenceIndex++) {
            if (listener != null && listener.isCancelled()) return null;
            String sentence = sentences.get(sentenceIndex);
            int sentenceStart = sentenceOffset; sentenceOffset += sentence.length();
            if (sentence.isEmpty() || skipUntil >= sentenceOffset) continue;

            boolean[] exactPositions = Arrays.copyOfRange(exactAll, sentenceStart, sentenceOffset);
            boolean[] blockedPositions = Arrays.copyOfRange(blockedAll, sentenceStart, sentenceOffset);
            boolean[] protectedPositions = blockedPositions.clone();
            for (int i = 0; i < protectedPositions.length; i++) protectedPositions[i] |= exactPositions[i];
            GrammarHit[] grammarHits = collectGrammarHits(sentence, fastMode, blockedPositions, exactPositions);
            List<MainActivity.TextBlock> intermediate = new ArrayList<>(Math.max(16, sentence.length() / 4));
            StringBuilder plain = new StringBuilder();
            int cursor = Math.max(0, skipUntil - sentenceStart);
            int originalStart = sentenceStart + cursor;
            while (cursor < sentence.length()) {
                if (listener != null && listener.isCancelled()) return null;

                MainActivity.TypoMatch typoMatch = dictionary.find(sentence, cursor, protectedPositions);
                Proofreader.Edit proof = proofEdits[sentenceStart + cursor];
                if (proof != null && (typoMatch == null || !typoMatch.custom)) {
                    flushPlain(intermediate, plain);
                    errorCount = appendProofChange(intermediate, proof.source, proof.replacement, proof.idiom, errorCount, listener);
                    skipUntil = proof.end;
                    cursor += proof.source.length(); continue;
                }
                if (typoMatch != null) {
                    flushPlain(intermediate, plain);
                    boolean real = !typoMatch.source.equals(typoMatch.correction);
                    int type = typoMatch.custom ? 4 : 2;
                    intermediate.add(new MainActivity.TextBlock(typoMatch.source, typoMatch.correction, real, 1.0f, type));
                    if (real) {
                        errorCount++;
                        if (listener != null) listener.onError("发现错误：" + typoMatch.source + " → " + typoMatch.correction + " | 共 " + errorCount + " 处", true);
                    }
                    cursor += typoMatch.source.length();
                    continue;
                }

                GrammarHit grammarHit = grammarHits[cursor];
                if (grammarHit != null) {
                    flushPlain(intermediate, plain);
                    String group1 = grammarHit.group1;
                    String group2 = grammarHit.group2;
                    String group3 = grammarHit.group3;
                    String[] selected = grammarHit.rule.options[0];
                    String replacement1 = selected[0] != null ? selected[0] : group1;
                    String replacement3 = selected.length > 1 && selected[1] != null ? selected[1] : group3;
                    // Numeric normalization can consume the same quantifier first (e.g. 2个电脑).
                    // Carry over the already collected, guarded computer rule without a second scan.
                    if ("个".equals(group3) && "个".equals(replacement3) && grammarHit.end > 0) {
                        GrammarHit computer = grammarHits[grammarHit.end - 1];
                        if (computer != null && "个".equals(computer.group1) && computer.group2.isEmpty()
                                && "电脑".equals(computer.group3) && "台".equals(computer.rule.options[0][0])) replacement3 = "台";
                    }
                    String explanation = selected.length > 2 && selected[2] != null ? selected[2] : "";

                    // 相邻冲突标点作为一个整体纠错：保留句末/分句标点，与桌面端一致。
                    // 这样删除一侧后，修正后的全文会把红色可点击标记落在实际保留下来的标点上，
                    // 而不是因为“删除结果长度为 0”错误地借用前一个汉字作为视觉锚点。
                    boolean punctuationConflict = "标点多余".equals(explanation) && group2.isEmpty()
                            && ((group1.matches("[，、]+") && group3.matches("[。；：]"))
                            || (group1.matches("[。；：]") && group3.matches("[，、]+")));
                    if (punctuationConflict && (replacement1.isEmpty() ^ replacement3.isEmpty())) {
                        String kept = group1.matches("[，、]+") ? group3 : group1;
                        // 若逗号/顿号一侧本身重复，只保留一个，避免“，，。”随机后留下“，，”。
                        if (kept.length() > 1 && kept.matches("[，、]+")) kept = kept.substring(0, 1);
                        String originalPunctuation = group1 + group3;
                        MainActivity.TextBlock block = new MainActivity.TextBlock(originalPunctuation, kept, true, 1.0f, 6);
                        block.exp = explanation;
                        intermediate.add(block);
                        errorCount++;
                        if (listener != null) listener.onError("发现错误：" + originalPunctuation + " → " + kept + " | 共 " + errorCount + " 处", true);
                        cursor = grammarHit.end;
                        continue;
                    }

                    // 非捕获部分也可能被规则删除；必须记录下来，确保逐项/全部还原不丢字。
                    errorCount = appendGrammarChange(intermediate, grammarHit.gaps[0], "", explanation, errorCount, listener);
                    errorCount = appendGrammarChange(intermediate, group1, replacement1, explanation, errorCount, listener);
                    errorCount = appendGrammarChange(intermediate, grammarHit.gaps[1], "", explanation, errorCount, listener);
                    appendNormalText(intermediate, group2);
                    errorCount = appendGrammarChange(intermediate, grammarHit.gaps[2], "", explanation, errorCount, listener);
                    errorCount = appendGrammarChange(intermediate, group3, replacement3, explanation, errorCount, listener);
                    errorCount = appendGrammarChange(intermediate, grammarHit.gaps[3], "", explanation, errorCount, listener);

                    cursor = grammarHit.end;
                    continue;
                }

                if (!protectedPositions[cursor] && cursor > 0 && cursor + 1 < sentence.length()) {
                    char number = sentence.charAt(cursor - 1), quantifier = sentence.charAt(cursor), noun = sentence.charAt(cursor + 1);
                    if (MainActivity.KNOWN_QUANTS.indexOf(quantifier) >= 0 && MainActivity.NUMS.indexOf(number) >= 0) {
                        MainActivity.QuantifierRule rule = MainActivity.quantRules.get(noun);
                        if (rule != null && rule.allowedQuants.indexOf(quantifier) < 0) {
                            char next = cursor + 2 < sentence.length() ? sentence.charAt(cursor + 2) : '\0';
                            if (MainActivity.isSafeCharAfterNoun(next)) {
                                flushPlain(intermediate, plain);
                                intermediate.add(new MainActivity.TextBlock(String.valueOf(quantifier), rule.primaryQuant, true, 1.0f, 3));
                                errorCount++;
                                if (listener != null) listener.onError("发现错误：" + number + quantifier + noun + " → " + number + rule.primaryQuant + noun + " | 共 " + errorCount + " 处", true);
                                cursor++;
                                continue;
                            }
                        }
                    }
                }

                char current = sentence.charAt(cursor++);
                if (isTarget(current)) {
                    flushPlain(intermediate, plain);
                    String value = String.valueOf(current);
                    intermediate.add(new MainActivity.TextBlock(value, value, false, 0f, 0));
                } else plain.append(current);
            }
            flushPlain(intermediate, plain);

            int originalPosition = originalStart;
            for (MainActivity.TextBlock block : intermediate) {
                if (block.type == 0) for (int i = originalPosition; i < originalPosition + block.original.length(); i++)
                    if (exactAll[i]) { block.type = 2; break; }
                originalPosition += block.original.length();
            }
            boolean candidateTarget = false;
            if (!fastMode) for (MainActivity.TextBlock block : intermediate) {
                if (block.type == 0 && block.current.length() == 1 && isTarget(block.current.charAt(0))) { candidateTarget = true; break; }
            }
            if (!fastMode && candidateTarget) {
            StringBuilder inferBuilder = new StringBuilder(sentence.length());
            for (MainActivity.TextBlock block : intermediate) inferBuilder.append(block.current);
            String inferText = inferBuilder.toString();
            MainActivity.TextBlock[] map = new MainActivity.TextBlock[inferText.length()];
            boolean[] ignored = new boolean[inferText.length()];
            int position = 0;
            for (MainActivity.TextBlock block : intermediate) {
                int length = block.current.length();
                Arrays.fill(map, position, position + length, block);
                if (block.type != 0) Arrays.fill(ignored, position, position + length, true);
                position += length;
            }
            markIgnoreWords(inferText, ignored);
            markProtectedTargets(inferText, ignored);

            boolean hasTarget = false;
            for (int i = 0; i < inferText.length(); i++) if (!ignored[i] && isTarget(inferText.charAt(i))) { hasTarget = true; break; }
            if (!fastMode && hasTarget) {
                if (!MainActivity.isTemperatureValid(temperature)) {
                    throw new IllegalArgumentException("温度参数必须在 0.5～2.0 之间");
                }
                FiveCharInference.Prediction prediction=FiveCharInference.predict(inferText,ignored,MainActivity.proTokenizer,MainActivity.proModule,temperature,()->listener!=null&&listener.isCancelled());
                if(prediction==null)return null;
                modelNanos+=prediction.modelNanos;modelCalls+=prediction.calls;reviewCalls+=prediction.reviews;
                for(int i=0;i<inferText.length();i++) {
                    int label=prediction.labels[i];if(label<0)continue;
                    String replacement=LABELS[label];float confidence=prediction.confidence[i];char character=inferText.charAt(i);
                    if(!replacement.equals(String.valueOf(character))&&confidence>=thresholds[label]) {
                        MainActivity.TextBlock block=map[i];block.current=replacement;block.modelCorrected=replacement;block.isMutable=true;block.conf=confidence;block.type=1;errorCount++;
                        if(listener!=null)listener.onError("发现错误："+character+" → "+replacement+" (置信度:"+String.format(Locale.getDefault(),"%.2f",confidence)+") | 共 "+errorCount+" 处",false);
                    }
                }
            }

            }

            List<MainActivity.TextBlock> finalSentence = MainActivity.mergeNormalBlocks(intermediate);
            for (MainActivity.TextBlock block : finalSentence) fullCleanText.append(block.current);
            allBlocks.add(finalSentence);
            long now = android.os.SystemClock.elapsedRealtime();
            if (listener != null && (now - lastProgressTime >= progressInterval(text.length()) || sentenceIndex == sentences.size() - 1)) {
                lastProgressTime = now;
                listener.onProgress(sentenceIndex + 1, sentences.size(), allBlocks, errorCount, now - startTime);
            }
        }
        long elapsed = android.os.SystemClock.elapsedRealtime() - startTime;
        Result result=new Result(allBlocks, fullCleanText.toString(), errorCount, elapsed); result.modelNanos=modelNanos;result.modelCalls=modelCalls;result.reviewCalls=reviewCalls;return result;
    }

    private static int progressInterval(int length) { return length > 100000 ? 1200 : (length > 30000 ? 700 : 350); }
    private static int appendProofChange(List<MainActivity.TextBlock> blocks, String source, String replacement, boolean idiom, int count, Listener listener) {
        // Keep only the changed characters in the review mark. A duplicate is a deletion, without a parenthetical note.
        int prefix=0,suffix=0;
        if(source.length()>replacement.length()&&!idiom){
            // Ordinary repetition keeps the suffix; idioms keep the prefix and delete later duplicates.
            while(suffix<replacement.length()&&source.charAt(source.length()-1-suffix)==replacement.charAt(replacement.length()-1-suffix))suffix++;
            while(prefix<replacement.length()-suffix&&source.charAt(prefix)==replacement.charAt(prefix))prefix++;
        }else{
            while(prefix<source.length()&&prefix<replacement.length()&&source.charAt(prefix)==replacement.charAt(prefix))prefix++;
            while(suffix<source.length()-prefix&&suffix<replacement.length()-prefix&&source.charAt(source.length()-1-suffix)==replacement.charAt(replacement.length()-1-suffix))suffix++;
        }
        appendProtectedText(blocks,source.substring(0,prefix));
        count=appendGrammarChange(blocks,source.substring(prefix,source.length()-suffix),replacement.substring(prefix,replacement.length()-suffix),"",count,listener);
        appendProtectedText(blocks,source.substring(source.length()-suffix));
        return count;
    }
    private static void appendProtectedText(List<MainActivity.TextBlock> blocks,String text) {
        if(!text.isEmpty())blocks.add(new MainActivity.TextBlock(text,text,false,0f,2));
    }
    private static int appendGrammarChange(List<MainActivity.TextBlock> blocks, String original, String replacement, String explanation, int count, Listener listener) {
        if (original.equals(replacement)) { appendNormalText(blocks, original); return count; }
        MainActivity.TextBlock block = new MainActivity.TextBlock(original, replacement, true, 1.0f, 6);
        block.exp = replacement.isEmpty() ? "" : explanation; blocks.add(block); count++;
        if (listener != null) listener.onError((replacement.isEmpty() ? "删除：" + original : "发现错误：" + original + " → " + replacement) + " | 共 " + count + " 处", true);
        return count;
    }
    private static boolean isTarget(char c) { return FiveCharInference.target(c); }
    private static void flushPlain(List<MainActivity.TextBlock> blocks, StringBuilder plain) {
        if (plain.length() == 0) return;
        String value = plain.toString(); blocks.add(new MainActivity.TextBlock(value, value, false, 0f, 0)); plain.setLength(0);
    }
    private static void appendNormalText(List<MainActivity.TextBlock> blocks, String text) {
        int runStart = 0;
        for (int i = 0; i < text.length(); i++) {
            if (!isTarget(text.charAt(i))) continue;
            if (i > runStart) { String run = text.substring(runStart, i); blocks.add(new MainActivity.TextBlock(run, run, false, 0f, 0)); }
            String target = String.valueOf(text.charAt(i)); blocks.add(new MainActivity.TextBlock(target, target, false, 0f, 0)); runStart = i + 1;
        }
        if (runStart < text.length()) { String run = text.substring(runStart); blocks.add(new MainActivity.TextBlock(run, run, false, 0f, 0)); }
    }
    private static void markIgnoreWords(String text, boolean[] ignored) {
        for (String word : MainActivity.IGNORE_WORDS) {
            int index = text.indexOf(word);
            while (index >= 0) {
                Arrays.fill(ignored, index, Math.min(ignored.length, index + word.length()), true);
                index = text.indexOf(word, index + 1);
            }
        }
    }
    private static void markProtectedTargets(String text, boolean[] ignored) {
        for (Pattern pattern : MainActivity.protectedTargetPatterns) {
            Matcher matcher = pattern.matcher(text);
            while (matcher.find()) {
                int index = matcher.start(1);
                if (index >= 0 && index < ignored.length && isTarget(text.charAt(index))) ignored[index] = true;
            }
        }
    }
    public static List<String> splitText(String text) {
        List<String> result=new ArrayList<>();int start=0;
        while(start<text.length()){
            int limit=Math.min(start+MAX_SEQUENCE_LENGTH,text.length()),end=limit;
            for(int i=start;i<limit;i++)if("。！？!?\n".indexOf(text.charAt(i))>=0){
                end=i+1;if(text.charAt(i)!='\n')while(end<limit&&"。！？!?，、；：”’\"」』".indexOf(text.charAt(end))>=0)end++;break;
            }
            if(end==limit&&end<text.length())for(int i=end-1;i>=Math.max(start+1,end-60);i--)if("，,；;、".indexOf(text.charAt(i))>=0){end=i+1;break;}
            if(end<text.length()&&Character.isLowSurrogate(text.charAt(end))&&Character.isHighSurrogate(text.charAt(end-1)))end--;
            if(end<text.length()&&text.charAt(end-1)=='\r'&&text.charAt(end)=='\n')end--;
            result.add(text.substring(start,end));start=end;
        }
        return result;
    }
}
DEDEDE_SOURCE_EOF

mkdir -p "app/src/main/java/com/app/dedede"
cat > "app/src/main/java/com/app/dedede/DededeApp.java" <<'DEDEDE_SOURCE_EOF'
package com.app.dedede;
import android.app.Application;
import android.content.Context;
import java.io.File;
public final class DededeApp extends Application {
    private static volatile Context appContext;
    @Override public void onCreate() {
        super.onCreate();
        appContext = getApplicationContext();
        migrateLegacyPreferences();
        clearRuntimePlainModels();
    }
    private void migrateLegacyPreferences() {
        migratePrefs("DedediConfig", "DededeConfig");
        migratePrefs("DedediModelIdle", "DededeModelIdle");
    }
    private void migratePrefs(String oldName, String newName) {
        android.content.SharedPreferences oldPrefs = getSharedPreferences(oldName, MODE_PRIVATE);
        android.content.SharedPreferences newPrefs = getSharedPreferences(newName, MODE_PRIVATE);
        if (!newPrefs.getAll().isEmpty() || oldPrefs.getAll().isEmpty()) return;
        android.content.SharedPreferences.Editor editor = newPrefs.edit();
        for (java.util.Map.Entry<String, ?> entry : oldPrefs.getAll().entrySet()) {
            Object value = entry.getValue(); String key = entry.getKey();
            if (value instanceof String) editor.putString(key, (String) value);
            else if (value instanceof Integer) editor.putInt(key, (Integer) value);
            else if (value instanceof Long) editor.putLong(key, (Long) value);
            else if (value instanceof Float) editor.putFloat(key, (Float) value);
            else if (value instanceof Boolean) editor.putBoolean(key, (Boolean) value);
            else if (value instanceof java.util.Set) {
                @SuppressWarnings("unchecked") java.util.Set<String> set = (java.util.Set<String>) value;
                editor.putStringSet(key, new java.util.HashSet<>(set));
            }
        }
        editor.apply();
    }
    private void clearRuntimePlainModels() {
        // 清理当前Dedede与旧Dededi版本异常退出时可能遗留的临时明文模型。
        for (String name : new String[]{"dedede_runtime_models", "dededi_runtime_models"}) {
            File dir = new File(getCacheDir(), name);
            File[] files = dir.listFiles((d, fileName) -> (fileName.endsWith(".pte") || fileName.endsWith(".pte.part") || fileName.endsWith(".onnx") || fileName.endsWith(".onnx.part")));
            if (files != null) for (File file : files) if (!file.delete()) file.deleteOnExit();
        }
    }
    static Context context() {
        Context value = appContext;
        if (value == null) throw new IllegalStateException("应用尚未初始化");
        return value;
    }
}
DEDEDE_SOURCE_EOF

mkdir -p "app/src/main/java/com/app/dedede"
cat > "app/src/main/java/com/app/dedede/DraftSync.java" <<'DEDEDE_SOURCE_EOF'
package com.app.dedede;

import android.content.SharedPreferences;

/** Revisioned text shared by the activity and floating editor. */
public final class DraftSync {
    public static final class Snapshot {
        public final String text;
        public final long revision;
        Snapshot(String text, long revision) { this.text = text; this.revision = revision; }
    }
    private DraftSync() {}
    public static synchronized Snapshot read(SharedPreferences preferences) {
        return new Snapshot(preferences.getString("sync_text", ""), preferences.getLong("sync_revision", 0L));
    }
    public static synchronized Snapshot publish(SharedPreferences preferences, String text) {
        Snapshot current = read(preferences);
        if (current.text.equals(text)) return current;
        long next = current.revision + 1L;
        preferences.edit().putString("sync_text", text).putLong("sync_revision", next).apply();
        return new Snapshot(text, next);
    }
    public static synchronized Snapshot publishIfCurrent(SharedPreferences preferences, String text, long revision) {
        Snapshot current = read(preferences);
        return current.revision == revision ? publish(preferences, text) : current;
    }
    public static boolean contentChanged(String removed, CharSequence text, int start, int count) {
        if (removed.length() != count) return true;
        for (int i = 0; i < count; i++) if (removed.charAt(i) != text.charAt(start + i)) return true;
        return false;
    }
    public static boolean resultIsStale(String input, String source, boolean hasResult) {
        return hasResult && (source == null || !source.equals(input));
    }
}
DEDEDE_SOURCE_EOF

mkdir -p "app/src/main/java/com/app/dedede"
cat > "app/src/main/java/com/app/dedede/FilePickerActivity.java" <<'DEDEDE_SOURCE_EOF'
package com.app.dedede;
import android.app.Activity;
import android.content.Intent;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.widget.Toast;
import androidx.core.content.ContextCompat;
import java.util.ArrayList;
import java.util.List;

public class FilePickerActivity extends Activity {
    @Override protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        Toast.makeText(this, "支持 txt、md、docx、pptx、pdf 及图片格式\n(最多支持上传20个)", Toast.LENGTH_LONG).show();
        Intent intent = new Intent(Intent.ACTION_GET_CONTENT);
        intent.setType("*/*");
        intent.putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true);
        intent.putExtra(Intent.EXTRA_MIME_TYPES, new String[]{"text/plain", "text/markdown", "application/vnd.openxmlformats-officedocument.wordprocessingml.document", "application/vnd.openxmlformats-officedocument.presentationml.presentation", "application/pdf", "image/*"});
        startActivityForResult(intent, 103);
    }

    @Override protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode != 103 || resultCode != RESULT_OK || data == null) { finish(); return; }
        List<Uri> uris = new ArrayList<>();
        if (data.getClipData() != null) {
            int count = data.getClipData().getItemCount();
            for (int i = 0; i < Math.min(count, 20); i++) uris.add(data.getClipData().getItemAt(i).getUri());
        } else if (data.getData() != null) {
            uris.add(data.getData());
        }
        if (uris.isEmpty()) { finish(); return; }
        Toast.makeText(this, "正在处理导入文件，请稍候...", Toast.LENGTH_SHORT).show();
        AppExecutors.IO.execute(() -> {
            StringBuilder combined = new StringBuilder(); String failure = "";
            for (int i = 0; i < uris.size(); i++) {
                if (isDestroyed() || isFinishing()) return;
                String text = MainActivity.extractTextFromUriSync(getApplicationContext(), uris.get(i), null);
                if (text != null && !text.trim().isEmpty()) {
                    if (combined.length() > 0) combined.append("\n\n---------------------------------\n\n");
                    combined.append(text);
                } else failure = MainActivity.getLastExtractError();
            }
            String finalText = combined.toString(), detail = failure;
            AppExecutors.MAIN.post(() -> {
                if (isDestroyed() || isFinishing()) return;
                if (!finalText.trim().isEmpty()) {
                    Intent serviceIntent = new Intent(this, FloatingService.class);
                    serviceIntent.putExtra("IMPORTED_TEXT", finalText);
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) ContextCompat.startForegroundService(this, serviceIntent);
                    else startService(serviceIntent);
                } else {
                    Toast.makeText(this, detail.isEmpty() ? "无法读取文件内容或内容为空" : "导入失败：" + detail, Toast.LENGTH_LONG).show();
                }
                finish();
            });
        });
    }
}
DEDEDE_SOURCE_EOF

mkdir -p "app/src/main/java/com/app/dedede"
cat > "app/src/main/java/com/app/dedede/FiveCharInference.java" <<'DEDEDE_SOURCE_EOF'
package com.app.dedede;
import java.util.Arrays;

/** Shared policy for both quantizations. No BOS/EOS; raw confidence gates review. */
public final class FiveCharInference {
    public static final String LABELS="的地得做作";
    public static final int REVIEW_RUN=2;
    public static final float REVIEW_CONFIDENCE=.78f;
    public interface Engine extends AutoCloseable {float[] forward(long[] ids,boolean[] mask) throws Exception;void close();}
    public interface Cancel {boolean stopped();}
    public static final class Prediction {
        public final int[] labels;public final float[] confidence;public final float[][] probabilities;
        public int calls,reviews;public long modelNanos;
        Prediction(int n){labels=new int[n];Arrays.fill(labels,-1);confidence=new float[n];probabilities=new float[n][];}
    }
    public static boolean target(char c){return LABELS.indexOf(c)>=0;}
    public static Prediction predict(String text,boolean[] ignored,HcamTokenizer tokenizer,Engine engine,float temperature,Cancel cancel) throws Exception {
        return predict(text,ignored,tokenizer,engine,temperature,cancel,REVIEW_RUN);
    }
    public static Prediction predict(String text,boolean[] ignored,HcamTokenizer tokenizer,Engine engine,float temperature,Cancel cancel,int reviewRun) throws Exception {
        if(ignored.length!=text.length())throw new IllegalArgumentException("保护位置长度异常");
        if(!Float.isFinite(temperature)||temperature<.5f||temperature>2f)throw new IllegalArgumentException("温度必须在0.5～2.0之间");
        if(reviewRun<2)throw new IllegalArgumentException("review 连续长度不得小于2");
        Prediction out=new Prediction(text.length());HcamTokenizer.Encoded enc=tokenizer.encode(text);int n=enc.ids.length;
        if(n>1248)throw new IllegalArgumentException("模型输入超过1248 tokens");
        boolean[] mask=new boolean[n];boolean active=false;
        for(int i=0;i<n;i++){int p=enc.starts[i];mask[i]=enc.ends[i]==p+1&&target(text.charAt(p));if(mask[i]&&!ignored[p])active=true;}
        if(!active)return out;
        if(cancel!=null&&cancel.stopped())return null;
        long start=System.nanoTime();float[] first=engine.forward(enc.ids,mask);out.modelNanos+=System.nanoTime()-start;out.calls++;validate(first,n);
        for(int i=0;i<n;i++){
            int p=enc.starts[i];if(!mask[i]||ignored[p])continue;if(cancel!=null&&cancel.stopped())return null;
            int group=LABELS.indexOf(text.charAt(p))<3?0:3,count=group==0?3:2;
            float[] raw=softmax(first,i*5+group,count,1f);int best=argmax(raw);float[] scores=first;
            int left=p,right=p;while(left>0&&target(text.charAt(left-1)))left--;while(right+1<text.length()&&target(text.charAt(right+1)))right++;
            if(right-left+1>=reviewRun&&raw[best]<REVIEW_CONFIDENCE){
                boolean[] single=new boolean[n];single[i]=true;start=System.nanoTime();scores=engine.forward(enc.ids,single);out.modelNanos+=System.nanoTime()-start;out.calls++;out.reviews++;validate(scores,n);
            }
            float[] probabilities=softmax(scores,i*5+group,count,temperature);best=argmax(probabilities);
            out.labels[p]=group+best;out.confidence[p]=probabilities[best];out.probabilities[p]=probabilities;
        }
        return out;
    }
    private static int argmax(float[] p){int k=0;for(int i=1;i<p.length;i++)if(p[i]>p[k])k=i;return k;}
    private static void validate(float[] scores,int n){if(scores==null||scores.length!=n*5)throw new IllegalStateException("模型输出必须为[1,L,5]，L="+n);for(float x:scores)if(!Float.isFinite(x))throw new IllegalStateException("模型输出包含 NaN/Infinity");}
    private static float[] softmax(float[] scores,int offset,int n,float temperature){
        double max=Double.NEGATIVE_INFINITY;for(int i=0;i<n;i++)max=Math.max(max,scores[offset+i]/(double)temperature);
        float[] p=new float[n];double sum=0;for(int i=0;i<n;i++){p[i]=(float)Math.exp(scores[offset+i]/(double)temperature-max);sum+=p[i];}for(int i=0;i<n;i++)p[i]/=sum;return p;
    }
}
DEDEDE_SOURCE_EOF

mkdir -p "app/src/main/java/com/app/dedede"
cat > "app/src/main/java/com/app/dedede/FloatingService.java" <<'DEDEDE_SOURCE_EOF'
package com.app.dedede;
import android.annotation.SuppressLint;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.graphics.PixelFormat;
import android.os.Build;
import android.os.IBinder;
import android.text.Editable;
import android.text.TextWatcher;
import android.view.Gravity;
import android.view.LayoutInflater;
import android.view.MotionEvent;
import android.view.View;
import android.view.WindowManager;
import android.widget.Button;
import android.widget.EditText;
import android.widget.ProgressBar;
import android.widget.TextView;
import android.widget.Toast;
import java.util.ArrayDeque;
import java.util.List;
import java.util.Locale;

public class FloatingService extends Service {
    private static final long MIN_LAST_ERROR_VISIBLE_MS = 1000L;
    private WindowManager windowManager;
    private View floatView, panelInput, circleSpin, statusContainer;
    private WindowManager.LayoutParams params;
    private EditText editFloatInput;
    private TextView tvStatus;
    private ProgressBar floatProgressBar;
    private Button btnFloatSwitch;
    private volatile boolean isChecking, isInterruptRequested, destroyed;
    private volatile long inferenceGeneration;
    private volatile String currentHistoryFileId;
    private String lastCorrectedText = "";
    private long lastErrorShownAt;
    private final Object errorStatusLock = new Object();
    private final ArrayDeque<String> visibleErrorLines = new ArrayDeque<>(3);
    private boolean errorStatusFlushScheduled;
    private SharedPreferences sp;
    private boolean restoringFloatInput, floatSyncDirty;
    private long floatDraftRevision;
    private final Runnable hideStatusRunnable = () -> { if (!destroyed && statusContainer != null) statusContainer.setVisibility(View.GONE); };
    private final Runnable errorStatusFlushRunnable = () -> {
        StringBuilder display = new StringBuilder();
        synchronized (errorStatusLock) {
            for (String line : visibleErrorLines) { if (display.length() > 0) display.append('\n'); display.append(line); }
            errorStatusFlushScheduled = false;
        }
        if (!destroyed && !isInterruptRequested && display.length() > 0) {
            tvStatus.setText(display.toString());
            statusContainer.setVisibility(View.VISIBLE);
            statusContainer.removeCallbacks(hideStatusRunnable);
            statusContainer.postDelayed(hideStatusRunnable, 5000);
            lastErrorShownAt = android.os.SystemClock.uptimeMillis();
        }
    };
    private final Runnable syncTextRunnable = () -> { if (!destroyed) flushFloatInputSync(); };

    private void publishFloatText(String text) {
        AppExecutors.MAIN.removeCallbacks(syncTextRunnable);
        floatDraftRevision = DraftSync.publish(sp, text).revision; floatSyncDirty = false;
    }
    private void flushFloatInputSync() {
        AppExecutors.MAIN.removeCallbacks(syncTextRunnable);
        if (!floatSyncDirty || sp == null || editFloatInput == null) return;
        String text = editFloatInput.getText().toString();
        DraftSync.Snapshot shared = DraftSync.publishIfCurrent(sp, text, floatDraftRevision);
        floatSyncDirty = false; floatDraftRevision = shared.revision;
        if (!shared.text.equals(text)) {
            restoringFloatInput = true;
            try { editFloatInput.setText(shared.text); } finally { restoringFloatInput = false; }
            currentHistoryFileId = null; lastCorrectedText = ""; MainActivity.hasNewFloatResult = false; MainActivity.pendingFloatSourceText = null;
            if (!destroyed) showStatus("其他窗口已更新文本，已同步最新内容。", true);
        }
    }
    private void refreshFloatInput() {
        flushFloatInputSync();
        DraftSync.Snapshot shared = DraftSync.read(sp); floatDraftRevision = shared.revision;
        if (shared.text.equals(editFloatInput.getText().toString())) return;
        restoringFloatInput = true;
        try { editFloatInput.setText(shared.text); } finally { restoringFloatInput = false; }
        currentHistoryFileId = null; lastCorrectedText = ""; MainActivity.hasNewFloatResult = false; MainActivity.pendingFloatSourceText = null;
    }

    @Override public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent != null && intent.hasExtra("IMPORTED_TEXT")) {
            String text = intent.getStringExtra("IMPORTED_TEXT");
            if (editFloatInput != null) MainActivity.checkAndPromptCleanup(this, text, cleaned -> {
                currentHistoryFileId = null;
                editFloatInput.setText(cleaned);
                publishFloatText(cleaned);
                saveHistory(cleaned, null);
                Toast.makeText(this, "导入成功", Toast.LENGTH_SHORT).show();
                if (panelInput.getVisibility() != View.VISIBLE) { panelInput.setVisibility(View.VISIBLE); setFocusable(true); }
            });
        }
        return START_NOT_STICKY;
    }

    @SuppressLint("ClickableViewAccessibility")
    @Override public void onCreate() {
        super.onCreate();
        sp = getSharedPreferences("DededeConfig", Context.MODE_PRIVATE);
        AppExecutors.INFERENCE.execute(() -> MainActivity.ensureTypoMapLoaded(getApplicationContext()));
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel channel = new NotificationChannel("float_chan", "悬浮窗后台服务", NotificationManager.IMPORTANCE_LOW);
            getSystemService(NotificationManager.class).createNotificationChannel(channel);
            Notification notification = new Notification.Builder(this, "float_chan").setContentTitle("纠错 Pro").setContentText("悬浮窗运行中").setSmallIcon(R.drawable.ic_dedede_fg).build();
            startForeground(1, notification);
        }
        windowManager = (WindowManager) getSystemService(WINDOW_SERVICE);
        int type = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O ? WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY : WindowManager.LayoutParams.TYPE_PHONE;
        params = new WindowManager.LayoutParams(WindowManager.LayoutParams.WRAP_CONTENT, WindowManager.LayoutParams.WRAP_CONTENT, type, WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE | WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH, PixelFormat.TRANSLUCENT);
        params.gravity = Gravity.TOP | Gravity.START; params.x = 0; params.y = 300;
        floatView = ((LayoutInflater) getSystemService(LAYOUT_INFLATER_SERVICE)).inflate(R.layout.layout_floating, null);
        panelInput = floatView.findViewById(R.id.panelInput); editFloatInput = floatView.findViewById(R.id.editFloatInput);
        circleSpin = floatView.findViewById(R.id.circleSpin); tvStatus = floatView.findViewById(R.id.tvStatus);
        statusContainer = floatView.findViewById(R.id.statusContainer); floatProgressBar = floatView.findViewById(R.id.floatProgressBar);
        View btnCircle = floatView.findViewById(R.id.btnCircle), panelTopBar = floatView.findViewById(R.id.panelTopBar);
        Button btnImport = floatView.findViewById(R.id.btnFloatImport), btnPaste = floatView.findViewById(R.id.btnFloatPaste), btnClear = floatView.findViewById(R.id.btnFloatClear), btnCheck = floatView.findViewById(R.id.btnFloatCheck), btnCopy = floatView.findViewById(R.id.btnFloatCopy), btnJump = floatView.findViewById(R.id.btnFloatJump), btnClose = floatView.findViewById(R.id.btnFloatCloseAll);
        btnFloatSwitch = floatView.findViewById(R.id.btnFloatSwitch);

        DraftSync.Snapshot initialDraft = DraftSync.read(sp);
        floatDraftRevision = initialDraft.revision; editFloatInput.setText(initialDraft.text);
        editFloatInput.addTextChangedListener(new TextWatcher() {
            String removed = ""; boolean actualChange;
            @Override public void beforeTextChanged(CharSequence s, int start, int count, int after) { removed = s.subSequence(start, start + count).toString(); }
            @Override public void onTextChanged(CharSequence s, int start, int before, int count) {
                actualChange = DraftSync.contentChanged(removed, s, start, count);
                if (actualChange && !restoringFloatInput && count > 2 && !MainActivity.isCleanDialogOpen) {
                    String chunk = s.subSequence(start, start + count).toString();
                    if (MainActivity.hasSymbolBurst(chunk)) AppExecutors.MAIN.post(() -> MainActivity.checkAndPromptCleanup(FloatingService.this, editFloatInput.getText().toString(), cleaned -> {
                        if (!cleaned.equals(editFloatInput.getText().toString())) {
                            MainActivity.isCleanDialogOpen = true; editFloatInput.setText(cleaned); editFloatInput.setSelection(cleaned.length()); publishFloatText(cleaned); MainActivity.isCleanDialogOpen = false;
                        }
                    }));
                }
            }
            @Override public void afterTextChanged(Editable s) {
                boolean changed = actualChange; actualChange = false;
                if (!changed || restoringFloatInput) return;
                if (!floatSyncDirty) floatDraftRevision = DraftSync.read(sp).revision;
                floatSyncDirty = true;
                if (isChecking) {
                    isInterruptRequested = true;
                    inferenceGeneration++;
                    isChecking = false;
                    btnFloatSwitch.setEnabled(true);
                    circleSpin.setVisibility(View.INVISIBLE);
                    floatProgressBar.setVisibility(View.GONE);
                    showStatus("原文已修改，本次纠错已中断。", true);
                }
                currentHistoryFileId = null;
                lastCorrectedText = "";
                MainActivity.hasNewFloatResult = false; MainActivity.pendingFloatSourceText = null;
                if (s.length() > 0 && !sp.getBoolean("is_fast_mode", false)) MainActivity.warmProEngineAsync(FloatingService.this);
                AppExecutors.MAIN.removeCallbacks(syncTextRunnable);
                AppExecutors.MAIN.postDelayed(syncTextRunnable, 400);
            }
        });

        floatView.setOnTouchListener((v, event) -> {
            if (event.getAction() == MotionEvent.ACTION_OUTSIDE) {
                if (MainActivity.isCleanDialogOpen) return true;
                if (panelInput.getVisibility() == View.VISIBLE) { panelInput.setVisibility(View.GONE); setFocusable(false); }
                return true;
            }
            return false;
        });

        btnImport.setOnClickListener(v -> { Intent intent = new Intent(this, FilePickerActivity.class); intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK); startActivity(intent); });
        btnPaste.setOnClickListener(v -> {
            ClipboardManager clipboard = (ClipboardManager) getSystemService(Context.CLIPBOARD_SERVICE);
            if (clipboard != null && clipboard.hasPrimaryClip() && clipboard.getPrimaryClip().getItemCount() > 0) {
                CharSequence value = clipboard.getPrimaryClip().getItemAt(0).getText();
                if (value != null) MainActivity.checkAndPromptCleanup(this, value.toString(), cleaned -> {
                    currentHistoryFileId = null; editFloatInput.setText(cleaned); publishFloatText(cleaned);
                    if (panelInput.getVisibility() != View.VISIBLE) { panelInput.setVisibility(View.VISIBLE); setFocusable(true); }
                });
            }
        });
        btnClear.setOnClickListener(v -> { currentHistoryFileId = null; lastCorrectedText = ""; editFloatInput.setText(""); });
        btnCheck.setOnClickListener(v -> {
            flushFloatInputSync();
            String text = editFloatInput.getText().toString();
            if (text.isEmpty()) { Toast.makeText(this, "文本为空", Toast.LENGTH_SHORT).show(); return; }
            if (currentHistoryFileId == null) currentHistoryFileId = java.util.UUID.randomUUID().toString();
            String fileId = currentHistoryFileId; saveHistory(text, fileId); setFocusable(false); panelInput.setVisibility(View.GONE); startInference(text, fileId);
        });
        btnCopy.setOnClickListener(v -> {
            String text = lastCorrectedText.isEmpty() ? editFloatInput.getText().toString() : lastCorrectedText;
            ClipboardManager clipboard = (ClipboardManager) getSystemService(Context.CLIPBOARD_SERVICE);
            if (clipboard != null) { clipboard.setPrimaryClip(ClipData.newPlainText("Corrected", text)); showStatus("已复制修正后的全文。", true); }
        });
        btnFloatSwitch.setOnClickListener(v -> {
            boolean fast = !sp.getBoolean("is_fast_mode", false); sp.edit().putBoolean("is_fast_mode", fast).apply(); showStatus(fast ? "已切换至极速模式" : "已切换至专业模式", true);
            if (!fast && editFloatInput.length() > 0) MainActivity.warmProEngineAsync(FloatingService.this);
        });

        Runnable jumpToApp = () -> {
            flushFloatInputSync();
            publishFloatText(editFloatInput.getText().toString());
            if (MainActivity.isEditorOpen) { Toast.makeText(this, "编辑模式中无法跳转，请先保存或退出。", Toast.LENGTH_SHORT).show(); return; }
            Intent intent = new Intent(this, MainActivity.class); intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_SINGLE_TOP); intent.putExtra("SYNC_TEXT", editFloatInput.getText().toString()); intent.putExtra("FROM_FLOAT_JUMP", true); startActivity(intent);
            panelInput.setVisibility(View.GONE); setFocusable(false);
        };
        btnJump.setOnClickListener(v -> jumpToApp.run()); btnClose.setOnClickListener(v -> stopSelf());

        View.OnTouchListener dragListener = new View.OnTouchListener() {
            int initialX, initialY; float initialTouchX, initialTouchY; boolean moved, longPressed;
            final Runnable longPress = () -> { longPressed = true; jumpToApp.run(); };
            @Override public boolean onTouch(View view, MotionEvent event) {
                switch (event.getActionMasked()) {
                    case MotionEvent.ACTION_DOWN:
                        initialX = params.x; initialY = params.y; initialTouchX = event.getRawX(); initialTouchY = event.getRawY(); moved = false; longPressed = false;
                        if (view.getId() == R.id.btnCircle) AppExecutors.MAIN.postDelayed(longPress, 500); return true;
                    case MotionEvent.ACTION_MOVE:
                        int dx = (int) (event.getRawX() - initialTouchX), dy = (int) (event.getRawY() - initialTouchY);
                        if (!moved && (Math.abs(dx) > 10 || Math.abs(dy) > 10)) { moved = true; AppExecutors.MAIN.removeCallbacks(longPress); }
                        if (moved && !destroyed) { params.x = initialX + dx; params.y = initialY + dy; try { windowManager.updateViewLayout(floatView, params); } catch (Exception ignored) {} }
                        return true;
                    case MotionEvent.ACTION_UP: case MotionEvent.ACTION_CANCEL:
                        AppExecutors.MAIN.removeCallbacks(longPress);
                        if (!moved && !longPressed && view.getId() == R.id.btnCircle) {
                            if (isChecking) { isInterruptRequested = true; showStatus("已中断", true); }
                            else {
                                boolean visible = panelInput.getVisibility() == View.VISIBLE;
                                if (!visible) {
                                    refreshFloatInput();
                                }
                                panelInput.setVisibility(visible ? View.GONE : View.VISIBLE); setFocusable(!visible);
                            }
                        }
                        return true;
                }
                return false;
            }
        };
        btnCircle.setOnTouchListener(dragListener); panelTopBar.setOnTouchListener(dragListener); panelInput.setOnTouchListener(dragListener);
        windowManager.addView(floatView, params);
    }

    private void saveHistory(String text, String fileId) {
        HistoryStore.save(this, sp, text, fileId, savedId -> {
            if (!destroyed && editFloatInput != null && text.equals(editFloatInput.getText().toString())) currentHistoryFileId = savedId;
        });
    }

    private void setFocusable(boolean focusable) {
        if (destroyed || floatView == null) return;
        params.flags = focusable ? WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL | WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH : WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE | WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH;
        try { windowManager.updateViewLayout(floatView, params); } catch (Exception ignored) {}
    }

    private void showStatus(String message, boolean autoHide) {
        AppExecutors.MAIN.post(() -> {
            if (destroyed) return;
            tvStatus.setText(message); statusContainer.setVisibility(View.VISIBLE); floatProgressBar.setVisibility(View.GONE); statusContainer.removeCallbacks(hideStatusRunnable);
            if (autoHide) statusContainer.postDelayed(hideStatusRunnable, 3000);
        });
    }

    private String compactErrorStatus(String message) {
        String value = message == null ? "" : message.replace("发现错误：", "").replace(" (置信度:", "（").replace(") | 共 ", "）｜共").replace(" | 共 ", "｜共");
        if (value.length() <= 24) return value;
        int suffixIndex = value.lastIndexOf("｜共");
        String suffix = suffixIndex >= 0 ? value.substring(suffixIndex) : "";
        int keep = Math.max(8, 23 - suffix.length());
        return value.substring(0, Math.min(keep, value.length())) + "…" + suffix;
    }

    private void showErrorStatus(String message) {
        synchronized (errorStatusLock) {
            visibleErrorLines.addLast(compactErrorStatus(message));
            while (visibleErrorLines.size() > 3) visibleErrorLines.removeFirst();
            if (!errorStatusFlushScheduled) {
                errorStatusFlushScheduled = true;
                AppExecutors.MAIN.postDelayed(errorStatusFlushRunnable, 40);
            }
        }
    }

    private void finishAfterLastErrorIsVisible(CorrectionCore.Result result, long generation) {
        AppExecutors.MAIN.post(new Runnable() {
            @Override public void run() {
                if (destroyed || isInterruptRequested || generation != inferenceGeneration) { finishInterrupted(generation); return; }
                synchronized (errorStatusLock) {
                    if (errorStatusFlushScheduled) {
                        AppExecutors.MAIN.postDelayed(this, 30);
                        return;
                    }
                }
                long visibleFor = android.os.SystemClock.uptimeMillis() - lastErrorShownAt;
                long delay = result.errorCount > 0 ? Math.max(0L, MIN_LAST_ERROR_VISIBLE_MS - visibleFor) : 0L;
                AppExecutors.MAIN.postDelayed(() -> finishSuccess(result, generation), delay);
            }
        });
    }

    private void startInference(String text, String fileId) {
        boolean fast = sp.getBoolean("is_fast_mode", false);
        float storedTemperature = MainActivity.parseFloatSafe(sp.getString("pro_temp", "1.0"), Float.NaN);
        if (!fast && !MainActivity.isTemperatureValid(storedTemperature)) {
            storedTemperature = 1.0f;
            sp.edit().putString("pro_temp", "1.0").apply();
            Toast.makeText(this, "温度参数无效，已自动恢复为1.0（允许范围0.5～2.0）", Toast.LENGTH_LONG).show();
        }
        final float temperature = fast ? 1f : storedTemperature;
        // 极速模式不使用模型；专业模式会在输入变动时预热，纠错结束后按使用间隔自适应保留30～120秒再释放。
        float tDe = MainActivity.parseFloatSafe(sp.getString("pro_th1", "0.7"), Float.NaN);
        float tDi = MainActivity.parseFloatSafe(sp.getString("pro_th2", "0.7"), Float.NaN);
        float tDe3 = MainActivity.parseFloatSafe(sp.getString("pro_th3", "0.75"), Float.NaN);
        float tZuo=MainActivity.parseFloatSafe(sp.getString("pro_th4","0.75"),Float.NaN),tZuo4=MainActivity.parseFloatSafe(sp.getString("pro_th5","0.75"),Float.NaN);
        if (!fast) MainActivity.noteProCorrectionStart(this);
        lastCorrectedText = "";
        MainActivity.hasNewFloatResult = false; MainActivity.pendingFloatSourceText = null;
        final long generation = ++inferenceGeneration;
        isChecking = true; isInterruptRequested = false; btnFloatSwitch.setEnabled(false); lastErrorShownAt = 0;
        synchronized (errorStatusLock) { visibleErrorLines.clear(); errorStatusFlushScheduled = false; }
        AppExecutors.MAIN.removeCallbacks(errorStatusFlushRunnable);
        showStatus("正在纠错……", false); floatProgressBar.setVisibility(View.VISIBLE); floatProgressBar.setProgress(0); circleSpin.setVisibility(View.VISIBLE);

        AppExecutors.INFERENCE.execute(() -> {
            boolean proAcquired = false;
            try {
                if (!fast) {
                    proAcquired = MainActivity.acquireProEngine(this);
                    if (!proAcquired) throw new IllegalStateException("专业 HCAM 模型加载失败：" + SecureAsset.lastErrorSummary());
                }
                CorrectionCore.Result result = CorrectionCore.run(text, fast, temperature, tDe, tDi, tDe3, tZuo, tZuo4, new CorrectionCore.Listener() {
                    @Override public boolean isCancelled() { return isInterruptRequested || destroyed || generation != inferenceGeneration; }
                    @Override public void onProgress(int current, int total, List<List<MainActivity.TextBlock>> completed, int errors, long elapsed) {
                        AppExecutors.MAIN.post(() -> { if (!destroyed && !isInterruptRequested && generation == inferenceGeneration) { floatProgressBar.setMax(total); floatProgressBar.setProgress(current); } });
                    }
                    @Override public void onError(String message, boolean minimumDisplay) { if (generation == inferenceGeneration && !isInterruptRequested) showErrorStatus(message); }
                });
                if (result == null || isInterruptRequested || destroyed || generation != inferenceGeneration) { finishInterrupted(generation); return; }
                lastCorrectedText = result.cleanText;
                MainActivity.pendingFloatBlocks = result.blocks; MainActivity.pendingFloatTimeMs = result.elapsedMs; MainActivity.pendingFloatFileId = fileId; MainActivity.pendingFloatSourceText = text; MainActivity.hasNewFloatResult = true;
                HistoryStore.saveBlocks(this, fileId, result.blocks, result.elapsedMs);
                AppExecutors.MAIN.post(() -> { if (MainActivity.instance != null && !MainActivity.instance.isFinishing()) MainActivity.instance.onFloatResultReady(); });
                finishAfterLastErrorIsVisible(result, generation);
            } catch (Throwable exception) {
                AppExecutors.MAIN.post(() -> {
                    if (destroyed || generation != inferenceGeneration) return; isChecking = false; btnFloatSwitch.setEnabled(true); circleSpin.setVisibility(View.INVISIBLE); floatProgressBar.setVisibility(View.GONE);
                    showStatus("纠错中断："+MainActivity.errorDetails(exception), false);
                });
            } finally {
                if (proAcquired) MainActivity.releaseProEngine();
            }
        });
    }

    private void finishInterrupted(long generation) {
        AppExecutors.MAIN.post(() -> { if (!destroyed && generation == inferenceGeneration) { isChecking = false; btnFloatSwitch.setEnabled(true); circleSpin.setVisibility(View.INVISIBLE); floatProgressBar.setVisibility(View.GONE); } });
    }

    private void finishSuccess(CorrectionCore.Result result, long generation) {
        if (destroyed || isInterruptRequested || generation != inferenceGeneration) { finishInterrupted(generation); return; }
        isChecking = false; btnFloatSwitch.setEnabled(true); circleSpin.setVisibility(View.INVISIBLE);
        String elapsed = String.format(Locale.getDefault(), "%.2f", result.elapsedMs / 1000.0);
        showStatus((result.errorCount == 0 ? "未发现错误" : "共更正 " + result.errorCount + " 处错误") + "，耗时 " + elapsed + " 秒", true);
        ClipboardManager clipboard = (ClipboardManager) getSystemService(Context.CLIPBOARD_SERVICE);
        if (clipboard != null) clipboard.setPrimaryClip(ClipData.newPlainText("Corrected", result.cleanText));
    }

    @Override public IBinder onBind(Intent intent) { return null; }
    @Override public void onDestroy() {
        flushFloatInputSync();
        destroyed = true; isInterruptRequested = true; inferenceGeneration++; AppExecutors.MAIN.removeCallbacks(syncTextRunnable); AppExecutors.MAIN.removeCallbacks(hideStatusRunnable); AppExecutors.MAIN.removeCallbacks(errorStatusFlushRunnable);
        synchronized (errorStatusLock) { visibleErrorLines.clear(); errorStatusFlushScheduled = false; }
        if (statusContainer != null) statusContainer.removeCallbacks(hideStatusRunnable);
        if (floatView != null && windowManager != null) try { windowManager.removeView(floatView); } catch (Exception ignored) {}
        super.onDestroy();
    }
}
DEDEDE_SOURCE_EOF

mkdir -p "app/src/main/java/com/app/dedede"
cat > "app/src/main/java/com/app/dedede/FlowLayout.java" <<'DEDEDE_SOURCE_EOF'
package com.app.dedede;
import android.content.Context;
import android.util.AttributeSet;
import android.view.View;
import android.view.ViewGroup;

public class FlowLayout extends ViewGroup {
    private int hGap = 20, vGap = 20;
    public FlowLayout(Context context) { super(context); }
    public FlowLayout(Context context, AttributeSet attrs) { super(context, attrs); }

    @Override protected void onMeasure(int widthMeasureSpec, int heightMeasureSpec) {
        int sizeWidth = MeasureSpec.getSize(widthMeasureSpec), modeWidth = MeasureSpec.getMode(widthMeasureSpec);
        int sizeHeight = MeasureSpec.getSize(heightMeasureSpec), modeHeight = MeasureSpec.getMode(heightMeasureSpec);
        int available = Math.max(0, sizeWidth - getPaddingLeft() - getPaddingRight());
        int measuredWidth = 0, measuredHeight = 0, lineWidth = 0, lineHeight = 0;
        for (int i = 0; i < getChildCount(); i++) {
            View child = getChildAt(i); if (child.getVisibility() == GONE) continue;
            measureChild(child, widthMeasureSpec, heightMeasureSpec);
            int childWidth = child.getMeasuredWidth(), childHeight = child.getMeasuredHeight();
            int required = lineWidth == 0 ? childWidth : lineWidth + hGap + childWidth;
            if (lineWidth > 0 && required > available) {
                measuredWidth = Math.max(measuredWidth, lineWidth); measuredHeight += lineHeight + vGap; lineWidth = childWidth; lineHeight = childHeight;
            } else {
                lineWidth = required; lineHeight = Math.max(lineHeight, childHeight);
            }
        }
        measuredWidth = Math.max(measuredWidth, lineWidth) + getPaddingLeft() + getPaddingRight();
        measuredHeight += lineHeight + getPaddingTop() + getPaddingBottom();
        setMeasuredDimension(modeWidth == MeasureSpec.EXACTLY ? sizeWidth : measuredWidth, modeHeight == MeasureSpec.EXACTLY ? sizeHeight : measuredHeight);
    }

    @Override protected void onLayout(boolean changed, int l, int t, int r, int b) {
        int available = getWidth() - getPaddingLeft() - getPaddingRight();
        int x = getPaddingLeft(), y = getPaddingTop(), lineWidth = 0, lineHeight = 0;
        for (int i = 0; i < getChildCount(); i++) {
            View child = getChildAt(i); if (child.getVisibility() == GONE) continue;
            int childWidth = child.getMeasuredWidth(), childHeight = child.getMeasuredHeight();
            int required = lineWidth == 0 ? childWidth : lineWidth + hGap + childWidth;
            if (lineWidth > 0 && required > available) { x = getPaddingLeft(); y += lineHeight + vGap; lineWidth = 0; lineHeight = 0; }
            if (lineWidth > 0) { x += hGap; lineWidth += hGap; }
            child.layout(x, y, x + childWidth, y + childHeight);
            x += childWidth; lineWidth += childWidth; lineHeight = Math.max(lineHeight, childHeight);
        }
    }
}
DEDEDE_SOURCE_EOF

mkdir -p "app/src/main/java/com/app/dedede"
cat > "app/src/main/java/com/app/dedede/HcamTokenizer.java" <<'DEDEDE_SOURCE_EOF'
package com.app.dedede;
import org.json.*;
import java.util.*;
import java.util.regex.*;

/** HCAM v6 character + Latin BPE, retaining original UTF-16 UI offsets. */
public final class HcamTokenizer {
    private final Map<String,Integer> vocab = new HashMap<>(), ranks = new HashMap<>();
    private final Set<String> latinVocab = new HashSet<>();
    private static final Pattern LATIN = Pattern.compile("\\p{IsLatin}[\\p{IsLatin}\\p{M}]*");
    public static final class Encoded {
        public final long[] ids; public final int[] starts, ends;
        Encoded(List<Long> tokens,List<Integer> a,List<Integer> b) {
            ids=new long[tokens.size()]; starts=new int[ids.length]; ends=new int[ids.length];
            for(int i=0;i<ids.length;i++){ids[i]=tokens.get(i);starts[i]=a.get(i);ends[i]=b.get(i);}
        }
    }
    public HcamTokenizer(String json) throws JSONException {
        JSONObject obj=new JSONObject(json);
        if(!"HCAM-character-latin-bpe-tokenizer".equals(obj.getString("format")) || obj.getInt("version")!=6 || !"selective_v1".equals(obj.getString("latin_case_policy"))) throw new IllegalArgumentException("HCAM V2 tokenizer 格式/版本不匹配");
        JSONArray pieces=obj.getJSONArray("pieces");
        if(pieces.length()!=23000) throw new IllegalArgumentException("HCAM V2 词表大小不匹配");
        for(int i=0;i<pieces.length();i++) if(vocab.put(pieces.getString(i),i)!=null) throw new IllegalArgumentException("词表包含重复项");
        String[] special={"<unk>","<pad>","<bos>","<eos>","<用户>","<助手>","<换行>","<段落>"};
        for(int i=0;i<special.length;i++) if(!special[i].equals(pieces.getString(i))) throw new IllegalArgumentException("特殊 token 不匹配");
        int[] expected={472,510,561,724,496};
        for(int i=0;i<5;i++) if(!Integer.valueOf(expected[i]).equals(vocab.get("的地得做作".substring(i,i+1)))) throw new IllegalArgumentException("目标字 token 不匹配");
        JSONObject bpe=new JSONObject(obj.getString("latin_bpe_json")).getJSONObject("model");
        Iterator<String> keys=bpe.getJSONObject("vocab").keys();while(keys.hasNext())latinVocab.add(keys.next());
        JSONArray merges=bpe.getJSONArray("merges");
        for(int i=0;i<merges.length();i++){JSONArray pair=merges.getJSONArray(i);ranks.put(pair.getString(0)+"\0"+pair.getString(1),i);}
    }
    private int id(String s){return vocab.getOrDefault(s,0);}
    private static boolean newline(char c){return c=='\r'||c=='\n'||c=='\u2028'||c=='\u2029';}
    static String normalizeLatin(String word){
        List<Integer> cased=new ArrayList<>();
        word.codePoints().forEach(c->{String x=new String(Character.toChars(c));if(!x.toLowerCase(Locale.ROOT).equals(x.toUpperCase(Locale.ROOT)))cased.add(c);});
        boolean upper=false,lower=false,title=!cased.isEmpty()&&Character.isUpperCase(cased.get(0));
        for(int i=0;i<cased.size();i++){int c=cased.get(i);upper|=Character.isUpperCase(c);lower|=Character.isLowerCase(c);if(i>0&&!Character.isLowerCase(c))title=false;}
        boolean keep=(cased.size()==1&&upper)||(upper&&!lower)||(upper&&lower&&!title);
        if(keep)return word;
        StringBuilder s=new StringBuilder();
        word.codePoints().forEach(c->{String orig=new String(Character.toChars(c));String low=orig.toLowerCase(Locale.ROOT);s.append(low.codePointCount(0,low.length())==1&&low.length()==orig.length()?low:orig);});
        return s.toString();
    }
    private void latin(String original,int offset,List<Long> ids,List<Integer> starts,List<Integer> ends){
        String word=normalizeLatin(original);List<String> parts=new ArrayList<>();
        word.codePoints().forEach(c->parts.add(new String(Character.toChars(c))));
        boolean fallback=parts.size()>128;
        for(String p:parts)if(!latinVocab.contains(p))fallback=true;
        if(!fallback){
            while(parts.size()>1){int best=-1,rank=Integer.MAX_VALUE;
                for(int i=0;i+1<parts.size();i++){Integer r=ranks.get(parts.get(i)+"\0"+parts.get(i+1));if(r!=null&&r<rank){rank=r;best=i;}}
                if(best<0)break;parts.set(best,parts.get(best)+parts.remove(best+1));
            }
            for(String p:parts)if(!vocab.containsKey(p))fallback=true;
        }
        if(fallback){parts.clear();word.codePoints().forEach(c->parts.add(new String(Character.toChars(c))));}
        int p=offset;for(String piece:parts){ids.add((long)id(piece));starts.add(p);p+=piece.length();ends.add(p);}
    }
    public Encoded encode(String text){
        List<Long> ids=new ArrayList<>();List<Integer> starts=new ArrayList<>(),ends=new ArrayList<>();
        Matcher latin=LATIN.matcher(text);
        for(int p=0;p<text.length();){
            int start=p,token;
            if(text.startsWith("<用户>",p)||text.startsWith("<助手>",p)){token=text.startsWith("<用户>",p)?4:5;p+=4;}
            else if(newline(text.charAt(p))){int count=0;while(p<text.length()&&newline(text.charAt(p))){if(text.charAt(p++)=='\r'&&p<text.length()&&text.charAt(p)=='\n')p++;count++;}token=count>=2?7:6;}
            else if(latin.region(p,text.length()).lookingAt()){int end=latin.end();latin(text.substring(p,end),p,ids,starts,ends);p=end;continue;}
            else {int cp=text.codePointAt(p);p+=Character.charCount(cp);token=cp>=0xe000&&cp<=0xe003?4+cp-0xe000:id(text.substring(start,p));}
            ids.add((long)token);starts.add(start);ends.add(p);
        }
        return new Encoded(ids,starts,ends);
    }
}
DEDEDE_SOURCE_EOF

mkdir -p "app/src/main/java/com/app/dedede"
cat > "app/src/main/java/com/app/dedede/HistoryStore.java" <<'DEDEDE_SOURCE_EOF'
package com.app.dedede;
import android.content.Context;
import android.content.SharedPreferences;
import android.text.Spannable;
import org.json.JSONArray;
import org.json.JSONObject;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.nio.charset.StandardCharsets;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.List;
import java.util.Locale;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicLong;

public final class HistoryStore {
    public interface Callback { void onSaved(String fileId); }
    private static final AtomicLong HISTORY_EPOCH = new AtomicLong();
    private HistoryStore() {}

    public static void save(Context context, SharedPreferences preferences, String text, String existingFileId, Callback callback) {
        if (text == null || text.trim().isEmpty()) return;
        Context appContext = context.getApplicationContext();
        final long epoch = HISTORY_EPOCH.get();
        AppExecutors.HISTORY.execute(() -> {
            if (epoch != HISTORY_EPOCH.get()) return;
            String resolvedId = existingFileId;
            synchronized (AppExecutors.HISTORY_LOCK) {
                if (epoch != HISTORY_EPOCH.get()) return;
                try {
                    JSONArray history = new JSONArray(preferences.getString("history_records", "[]"));
                    int hash = text.hashCode(), length = text.length();
                    if ((resolvedId == null || resolvedId.isEmpty()) && history.length() > 0) {
                        JSONObject latest = history.getJSONObject(0);
                        if (latest.optInt("textHash", Integer.MIN_VALUE) == hash && latest.optInt("textLength", length) == length) {
                            String candidateId = latest.optString("file", "");
                            File candidate = new File(new File(appContext.getFilesDir(), "history"), candidateId + ".txt");
                            if (!candidateId.isEmpty() && text.equals(readUtf8(candidate))) {
                                resolvedId = candidateId;
                                String finalId = resolvedId;
                                if (callback != null) AppExecutors.MAIN.post(() -> callback.onSaved(finalId));
                                return;
                            }
                        }
                    }
                    if (resolvedId == null || resolvedId.isEmpty()) resolvedId = UUID.randomUUID().toString();
                    File directory = new File(appContext.getFilesDir(), "history");
                    if (!directory.exists() && !directory.mkdirs()) throw new IllegalStateException("无法创建历史目录");
                    writeUtf8Atomic(new File(directory, resolvedId + ".txt"), text);

                    JSONArray remaining = new JSONArray();
                    for (int i = 0; i < history.length(); i++) {
                        JSONObject object = history.getJSONObject(i);
                        if (!resolvedId.equals(object.optString("file", ""))) remaining.put(object);
                    }
                    JSONObject record = new JSONObject();
                    record.put("time", new SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault()).format(new Date()));
                    record.put("textHash", hash); record.put("textLength", length);
                    record.put("preview", text.length() > 16 ? text.substring(0, 16).replace("\n", " ") + "..." : text.replace("\n", " "));
                    record.put("file", resolvedId);
                    JSONArray finalArray = new JSONArray(); finalArray.put(record);
                    int keep = Math.min(remaining.length(), 49);
                    for (int i = 0; i < keep; i++) finalArray.put(remaining.getJSONObject(i));
                    for (int i = 49; i < remaining.length(); i++) deleteFiles(directory, remaining.getJSONObject(i).optString("file", ""));
                    if (epoch != HISTORY_EPOCH.get()) return;
                    preferences.edit().putString("history_records", finalArray.toString()).apply();
                } catch (Exception ignored) {}
            }
            String finalId = resolvedId;
            if (epoch == HISTORY_EPOCH.get() && callback != null) AppExecutors.MAIN.post(() -> callback.onSaved(finalId));
        });
    }

    public static void saveBlocks(Context context, String fileId, List<List<MainActivity.TextBlock>> blocks) {
        saveBlocks(context, fileId, blocks, -1L);
    }

    public static void saveBlocks(Context context, String fileId, List<List<MainActivity.TextBlock>> blocks, long elapsedMs) {
        if (fileId == null || fileId.isEmpty() || blocks == null || blocks.isEmpty()) return;
        Context appContext = context.getApplicationContext();
        final long epoch = HISTORY_EPOCH.get();
        AppExecutors.HISTORY.execute(() -> {
            if (epoch != HISTORY_EPOCH.get()) return;
            String json = MainActivity.serializeBlocks(blocks);
            synchronized (AppExecutors.HISTORY_LOCK) {
                if (epoch != HISTORY_EPOCH.get()) return;
                try {
                    File directory = new File(appContext.getFilesDir(), "history");
                    if (!directory.exists() && !directory.mkdirs()) throw new IllegalStateException("无法创建历史目录");
                    writeUtf8Atomic(new File(directory, fileId + "_blocks.json"), json);

                    String currentText = readUtf8(new File(directory, fileId + ".txt"));
                    if (currentText.isEmpty()) return;

                    SharedPreferences preferences = appContext.getSharedPreferences("DededeConfig", Context.MODE_PRIVATE);
                    JSONArray history = new JSONArray(preferences.getString("history_records", "[]"));
                    JSONArray deduplicated = new JSONArray();
                    int currentHash = currentText.hashCode();
                    int currentLength = currentText.length();
                    boolean changed = false;

                    for (int i = 0; i < history.length(); i++) {
                        JSONObject record = history.getJSONObject(i);
                        String otherId = record.optString("file", "");
                        if (fileId.equals(otherId)) {
                            if (elapsedMs >= 0L && record.optLong("elapsedMs", -1L) != elapsedMs) {
                                record.put("elapsedMs", elapsedMs);
                                changed = true;
                            }
                            deduplicated.put(record);
                            continue;
                        }

                        boolean sameTextMetadata =
                                record.optInt("textHash", Integer.MIN_VALUE) == currentHash
                                        && record.optInt("textLength", -1) == currentLength;

                        if (sameTextMetadata && !otherId.isEmpty()) {
                            String otherText = readUtf8(new File(directory, otherId + ".txt"));
                            String otherBlocks = readUtf8(new File(directory, otherId + "_blocks.json"));
                            if (currentText.equals(otherText) && json.equals(otherBlocks)) {
                                deleteFiles(directory, otherId);
                                changed = true;
                                continue;
                            }
                        }
                        deduplicated.put(record);
                    }

                    if (changed && epoch == HISTORY_EPOCH.get()) preferences.edit().putString("history_records", deduplicated.toString()).apply();
                } catch (Exception ignored) {}
            }
        });
    }

    public static void saveManual(Context context, String fileId, Spannable text) {
        if (fileId == null || fileId.isEmpty() || text == null) return;
        Context appContext = context.getApplicationContext();
        final long epoch = HISTORY_EPOCH.get();
        AppExecutors.HISTORY.execute(() -> {
            if (epoch != HISTORY_EPOCH.get()) return;
            String json = MainActivity.serializeSpannable(text);
            try {
                File directory = new File(appContext.getFilesDir(), "history"); if (!directory.exists()) directory.mkdirs();
                writeUtf8Atomic(new File(directory, fileId + "_manual.json"), json);
            } catch (Exception ignored) {}
        });
    }

    public static String readUtf8(File file) {
        if (file == null || !file.exists()) return "";
        try (FileInputStream input = new FileInputStream(file); ByteArrayOutputStream output = new ByteArrayOutputStream((int) Math.min(file.length(), 1_048_576))) {
            byte[] buffer = new byte[8192]; int read;
            while ((read = input.read(buffer)) != -1) output.write(buffer, 0, read);
            return output.toString(StandardCharsets.UTF_8.name());
        } catch (Exception ignored) { return ""; }
    }

    public static void deleteRecord(Context context, String fileId) {
        if (fileId == null || fileId.isEmpty()) return;
        deleteFiles(new File(context.getFilesDir(), "history"), fileId);
    }

    public static void clear(Context context) {
        HISTORY_EPOCH.incrementAndGet();
        synchronized (AppExecutors.HISTORY_LOCK) {
            File directory = new File(context.getFilesDir(), "history");
            File[] files = directory.listFiles();
            if (files != null) for (File file : files) file.delete();
        }
    }

    private static void deleteFiles(File directory, String fileId) {
        if (fileId == null || fileId.isEmpty()) return;
        new File(directory, fileId + ".txt").delete();
        new File(directory, fileId + "_blocks.json").delete();
        new File(directory, fileId + "_manual.json").delete();
    }

    private static void writeUtf8Atomic(File target, String content) throws Exception {
        File temporary = new File(target.getAbsolutePath() + ".tmp");
        try (FileOutputStream output = new FileOutputStream(temporary);
             java.io.BufferedWriter writer = new java.io.BufferedWriter(new java.io.OutputStreamWriter(output, StandardCharsets.UTF_8), 32768)) {
            writer.write(content); writer.flush(); output.getFD().sync();
        }
        try {
            android.system.Os.rename(temporary.getAbsolutePath(), target.getAbsolutePath());
        } catch (Exception exception) {
            temporary.delete();
            throw exception;
        }
    }
}
DEDEDE_SOURCE_EOF

mkdir -p "app/src/main/java/com/app/dedede"
cat > "app/src/main/java/com/app/dedede/MainActivity.java" <<'DEDEDE_SOURCE_EOF'
package com.app.dedede;
import android.animation.Animator;
import android.animation.AnimatorListenerAdapter;
import android.annotation.SuppressLint;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.graphics.Bitmap;
import android.graphics.Color;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.text.Editable;
import android.text.Html;
import android.text.InputFilter;
import android.text.Layout;
import android.text.Spannable;
import android.text.SpannableString;
import android.text.SpannableStringBuilder;
import android.text.Spanned;
import android.text.TextPaint;
import android.text.TextWatcher;
import android.text.method.LinkMovementMethod;
import android.text.style.BackgroundColorSpan;
import android.text.style.ClickableSpan;
import android.text.style.ForegroundColorSpan;
import android.text.style.StrikethroughSpan;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewAnimationUtils;
import android.view.ViewGroup;
import android.view.WindowManager;
import android.view.inputmethod.InputMethodManager;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import android.widget.RadioButton;
import android.widget.RadioGroup;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;
import androidx.appcompat.app.AlertDialog;
import androidx.appcompat.app.AppCompatActivity;
import androidx.core.view.GravityCompat;
import androidx.drawerlayout.widget.DrawerLayout;
import com.google.android.gms.tasks.Tasks;
import com.google.mlkit.vision.common.InputImage;
import com.google.mlkit.vision.text.Text;
import com.google.mlkit.vision.text.TextRecognition;
import com.google.mlkit.vision.text.TextRecognizer;
import com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions;
import org.json.JSONArray;
import org.json.JSONObject;
import java.io.BufferedReader;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Iterator;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.Stack;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public class MainActivity extends AppCompatActivity {
    static { System.loadLibrary("dedede"); }

    public static MainActivity instance;
    public static volatile ModelEngine proModule;
    private static final Object PRO_MODEL_LOCK = new Object();
    private static final Handler PRO_MODEL_HANDLER = new Handler(Looper.getMainLooper());
    private static final IdlePolicy PRO_IDLE = new IdlePolicy();
    private static final AtomicBoolean proWarmQueued = new AtomicBoolean();
    private static SharedPreferences proIdlePreferences;
    private static long proIdleLastSave;
    // This lock only guards a few scalar values. No model work or disk IO runs inside it.
    // Adaptive learning is based strictly on: previous correction finished -> next correction started.
    // Typing/prewarm activity may keep the model alive, but never becomes a learning sample.
    static final class IdlePolicy {
        static final long MIN_MS = 30_000L, MAX_MS = 120_000L;
        private long timeout = 60_000L, lastActivity, lastCorrectionFinished;
        synchronized void restore(long saved) { timeout = Math.max(MIN_MS, Math.min(MAX_MS, saved)); }
        synchronized void activity(long now) { lastActivity = now; }
        synchronized boolean correctionStarted(long now) {
            long old = timeout;
            if (lastCorrectionFinished > 0L) {
                long gap = now - lastCorrectionFinished;
                if (gap >= 5_000L && gap <= 300_000L) {
                    long goal = Math.max(MIN_MS, Math.min(MAX_MS, gap + 10_000L));
                    timeout = Math.max(MIN_MS, Math.min(MAX_MS, timeout + Math.round((goal - timeout) * 0.2)));
                }
            }
            lastActivity = now;
            return old != timeout;
        }
        synchronized void correctionFinished(long now) {
            lastCorrectionFinished = now;
            lastActivity = now;
        }
        synchronized long timeout() { return timeout; }
        synchronized long remaining(long now) { return Math.max(0L, timeout - Math.max(0L, now - lastActivity)); }
    }
    private static void loadIdlePolicy(Context context) {
        if (proIdlePreferences != null) return;
        proIdlePreferences = context.getSharedPreferences("DededeModelIdle", MODE_PRIVATE);
        PRO_IDLE.restore(proIdlePreferences.getLong("timeout_ms", 60_000L));
    }
    private static void persistIdlePolicy() {
        long now = android.os.SystemClock.uptimeMillis();
        if (proIdlePreferences != null && now - proIdleLastSave >= 60_000L) {
            long value = PRO_IDLE.timeout();
            if (proIdlePreferences.getLong("timeout_ms", 60_000L) != value) proIdlePreferences.edit().putLong("timeout_ms", value).apply();
            proIdleLastSave = now;
        }
    }
    private static int proModuleUsers;
    private static File proPlainModelFile;
    private static final Runnable PRO_MODEL_RELEASE_TASK = () -> AppExecutors.INFERENCE.execute(MainActivity::releaseProEngineNowIfIdle);
    public static volatile HcamTokenizer proTokenizer;
    public static volatile boolean proVocabReady;
    public static long clsId = 2L, sepId = 3L, maskId = -1L, unkId = 0L;
    public static final float MIN_TEMPERATURE = 0.5f;
    public static final float MAX_TEMPERATURE = 2.0f;
    private static volatile TypoIndex typoIndex = TypoIndex.build(new HashMap<>(), new HashSet<>(), new HashMap<>());
    private static final Pattern TYPO_FIELDS = Pattern.compile("\\s+");
    public static TypoIndex currentTypoIndex() { return typoIndex; }
    public static volatile boolean typoMapLoaded, isCleanDialogOpen, isEditorOpen, hasNewFloatResult;
    private static volatile boolean processSessionInitialized;
    public static List<List<TextBlock>> allSentencesBlocks = new ArrayList<>(), pendingFloatBlocks = new ArrayList<>();
    public static long lastTimeMs, pendingFloatTimeMs;
    public static String pendingFloatFileId;
    public static volatile String pendingFloatSourceText;

    public interface TextCleanCallback { void onCleaned(String text); }
    public interface TextExtractCallback { void onStart(); void onProgress(int progress, int max); void onExtracted(String text); }

    public static String errorDetails(Throwable error) {
        StringBuilder out=new StringBuilder();for(int i=0;error!=null&&i<6;i++,error=error.getCause()){if(i>0)out.append("\n原因：");out.append(error.getClass().getSimpleName()).append(": ").append(error.getMessage());}return out.toString();
    }
    private static void showModelError(String message) {
        AppExecutors.MAIN.post(()->{MainActivity a=instance;if(a!=null&&!a.isDestroyed()&&!a.isFinishing()&&a.outputText!=null)a.outputText.setText(message);});
    }

    public static float parseFloatSafe(String value, float fallback) {
        try { float parsed = Float.parseFloat(value); return Float.isFinite(parsed) ? parsed : fallback; } catch (Exception ignored) { return fallback; }
    }

    public static boolean isTemperatureValid(float temperature) {
        return Float.isFinite(temperature) && temperature >= MIN_TEMPERATURE && temperature <= MAX_TEMPERATURE;
    }

    public static float sanitizeTemperature(String value, float fallback) {
        float parsed = parseFloatSafe(value, fallback);
        return isTemperatureValid(parsed) ? parsed : fallback;
    }

    private static int countLettersOrDigits(CharSequence text, int start, int end) {
        if (text == null || text.length() == 0) return 0;
        int safeStart = Math.max(0, Math.min(start, text.length()));
        int safeEnd = Math.max(safeStart, Math.min(end, text.length()));
        int count = 0;
        for (int i = safeStart; i < safeEnd; i++) if (Character.isLetterOrDigit(text.charAt(i))) count++;
        return count;
    }

    private static int countWithPunctuation(CharSequence text, int start, int end) {
        if (text == null || text.length() == 0) return 0;
        int safeStart = Math.max(0, Math.min(start, text.length()));
        int safeEnd = Math.max(safeStart, Math.min(end, text.length()));
        int count = 0;
        for (int i = safeStart; i < safeEnd; ) {
            int cp = Character.codePointAt(text, i);
            if (!Character.isWhitespace(cp) && cp != 0x3000) count++;
            i += Character.charCount(cp);
        }
        return count;
    }

    public static boolean hasSymbolBurst(CharSequence text) {
        int stars = 0, hashes = 0, dashes = 0;
        for (int i = 0; i < text.length(); i++) {
            char c = text.charAt(i);
            if (c == '*' && ++stars >= 4) return true;
            if (c == '#' && ++hashes >= 4) return true;
            if (c == '-' && ++dashes >= 4) return true;
        }
        return false;
    }

    public static void checkAndPromptCleanup(Context context, String text, TextCleanCallback callback) {
        if (isCleanDialogOpen || text == null || text.isEmpty()) { if (callback != null) callback.onCleaned(text); return; }
        int stars = 0, hashes = 0, dashes = 0;
        for (int i = 0; i < text.length(); i++) { char c = text.charAt(i); if (c == '*') stars++; else if (c == '#') hashes++; else if (c == '-') dashes++; }
        if (stars < 4 && hashes < 4 && dashes < 4) { if (callback != null) callback.onCleaned(text); return; }
        isCleanDialogOpen = true; SymbolCleanActivity.callback = callback;
        Intent intent = new Intent(context, SymbolCleanActivity.class); intent.putExtra("raw_text", text); intent.putExtra("star", stars >= 4); intent.putExtra("hash", hashes >= 4); intent.putExtra("dash", dashes >= 4); intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP); context.startActivity(intent);
    }

    public static class QuantifierRule {
        public final String primaryQuant, allowedQuants;
        QuantifierRule(String primary, String allowed) { primaryQuant = primary; allowedQuants = allowed; }
    }
    public static class GramRule {
        public final Pattern pattern; public final String[][] options; public final boolean professionalOnly;
        GramRule(String regex, String[][] options, boolean professionalOnly) { pattern = Pattern.compile(regex); this.options = options; this.professionalOnly = professionalOnly; }
    }
    public static final Map<Character, QuantifierRule> quantRules = new HashMap<>();
    public static final List<GramRule> gramRules = new ArrayList<>();
    public static final List<Pattern> protectedTargetPatterns = new ArrayList<>();
    private static boolean rulesAttempted;

    private static void addRule(String regex, String[][] options) { gramRules.add(new GramRule(regex, options, false)); }
    private static void addProfessionalRule(String regex, String[][] options) { gramRules.add(new GramRule(regex, options, true)); }
    private static void addProtectedTargetPattern(String regex) { protectedTargetPatterns.add(Pattern.compile(regex)); }

    public static synchronized void ensureRulesLoaded() {
        if (rulesAttempted) return;
        rulesAttempted = true;
        try {
            // Prevent HCAM from changing 期待地搓手手 into 期待的搓手手.
            addProtectedTargetPattern("期待(地)(?=搓手手)");
            addProtectedTargetPattern("([做作])(?=的(?:判断|决定))");
            addProtectedTargetPattern("(?:^|[。！？!?…\\n“‘\"：:])[ 　]*(得)(?=[，,])");
            addProtectedTargetPattern("没(?:发生|看见|听见|这回事)(得)(?=了(?:呗|吧|嘛))");
            addProtectedTargetPattern("做(的)(?=作业)");
            addProtectedTargetPattern("(?:做|办|安排|处理)(得)(?=天衣无缝)");
            addProtectedTargetPattern("(?:高兴|开心|兴奋|激动)(得)(?=流下眼泪)");
            addProtectedTargetPattern("(地)(?=理(?:作业|课|知识|位置|环境|条件|信息|数据))");
            addProtectedTargetPattern("([做作])(?=出)");
            addProtectedTargetPattern("当([做作])");
            addProtectedTargetPattern("([做作])(?=了充分的准备)");
            addProtectedTargetPattern("([做作])(?=的说明)");
            addProtectedTargetPattern("(做)(?=的(?:原因|选择))");
            addProtectedTargetPattern("(作)(?=的诗)");
            addProtectedTargetPattern("说(得)(?=倒轻巧)");
            addProtectedTargetPattern("(?:做|说|写|唱|跑)(得)(?=的确)");
            addProtectedTargetPattern("[“‘\"「『](的)地得(?:做作)?(?=[”’\"」』])");
            addProtectedTargetPattern("[“‘\"「『]的(地)得(?:做作)?(?=[”’\"」』])");
            addProtectedTargetPattern("[“‘\"「『]的地(得)(?:做作)?(?=[”’\"」』])");
            addProtectedTargetPattern("[“‘\"「『]的地得(做)作(?=[”’\"」』])");
            addProtectedTargetPattern("[“‘\"「『]的地得做(作)(?=[”’\"」』])");
            addProtectedTargetPattern("(地)(?=图)");
            addProtectedTargetPattern("地热(的)(?=利用)");
            // 连续“得得得”的保护不在这里写规则，改由内置白名单常驻保护（见 loadTypoMap 中的内置白名单数组）。
            addRule("(给|为)([^，,。；;！？!?：:\n]{1,24}?)(让坐)(?!下|在|到|着|落|稳)", new String[][]{{null, "让座"}});
            addRule("(?:(?<=[一二两三四五六七八九十百千万这那几某0-9买换有要带借拿送租弄])|^)(个)()(电脑)(?!游戏|软件|程序|系统|应用|品牌|型号|配件|主板|屏幕|键盘|鼠标|电源|机箱|硬盘|显卡|内存|接口|文件|病毒|桌面|窗口|图标|账户|账号|网站|网络|课程|专业|公司|商店|维修|问题|高手|天才|爱好者|玩家|用户|工程师|技术|知识|操作|设置|配置|版本|模拟器|控制器)(?=$|[^\u4E00-\u9FFF]|[的了着过是在被把让给对和与同或就也都还很太真会能可要想走跑跳吃喝咬叫哭笑我看你他她它们这那买卖送坏出装用])", new String[][]{{"台", null}});
            addRule("(大概|大约)((?:有|是|持续了|持续|需要|花了|花费了|耗时|等了)?[ 　]*[0-9零〇一二两三四五六七八九十百千万亿]+(?:\\.[0-9]+)?[ 　]*(?:亿元|万元|亿|万|千|平方公里|平方米|立方米|公里|千米|厘米|毫米|千克|公斤|小时|分钟|个人|个月|岁|元|人|名|位|个|天|年|月|日|米|吨|斤|克|次|台|辆|本|件|层|楼|%|％)?(?:出头)?[ 　]*)(左右|上下)(?=$|[的，,。；;！？!?：:\\n])", new String[][]{{null, ""}});
            addRule("(?<!不)(超过|高于|高过|高达|多达)([ 　]*(?:[0-9]+(?:\\.[0-9]+)?|[零〇一二两三四五六七八九十百千万亿]+)[ 　]*(?:元|人|名|个|岁|天|年|米|公里|千克|公斤|吨|次|台|辆|本|%|％)?[ 　]*)(以上)(?=$|[的，,。；;！？!?：:\\n])", new String[][]{{null, ""}});
            addRule("(?<!不)(低于|少于|不足)([ 　]*(?:[0-9]+(?:\\.[0-9]+)?|[零〇一二两三四五六七八九十百千万亿]+)[ 　]*(?:元|人|名|个|岁|天|年|米|公里|千克|公斤|吨|次|台|辆|本|%|％)?[ 　]*)(以下)(?=$|[的，,。；;！？!?：:\\n])", new String[][]{{null, ""}});
            addRule("(截至|截止到)([^，,。；;！？!?：:、\\n]{1,15}?)(为止)", new String[][]{{null, ""}, {"", null}});
            // 回归删除："涉及到"在实际文本中大量合法使用（10误改/0正确），不再删除"到"。
            addRule("(付诸|诉诸|见诸)( *)(于)", new String[][]{{null, ""}});
            addRule("(互相|相互)( *)(厮打|角逐|探讨|商榷)", new String[][]{{"", null}});
            addRule("(第一|最佳|首要)( *)(首选)", new String[][]{{"", null}});
            addRule("(并非)( *)(是)", new String[][]{{null, ""}, {"并不", null}});
            addRule("(无时无刻)( *)(都)", new String[][]{{null, "不"}});
            addRule("(靠的是)([^，,。；;！？!?：:\n]{1,24}?)(取得的|获得的|实现的|达成的)(?=[，,。；;！？!?：:\n]|$)", new String[][]{{null, "", "句式杂糅"}});
            addRule("(成分是|主要成分是)([^，,。；;！？!?：:\n]{1,24}?)(配制而成的)(?=[，,。；;！？!?：:\n]|$)", new String[][]{{null, "", "句式杂糅"}});
            addRule("(成分有|主要成分有)([^，,。；;！？!?：:\n]{1,24}?)(配制而成的)(?=[，,。；;！？!?：:\n]|$)", new String[][]{{null, "", "句式杂糅"}});
            // “达到145万左右”等可能是正常估计，不把谓语擅自改成“有”。
            addRule("(几(?:十|百|千|万|亿)?|十几|几十|百余|千余|万余|亿余|数十|数百|数千|数万|数十万|数百万|数千万|数亿|上百|上千|上万|上亿|上百万|上千万|成百上千|成千上万|二三十|三四十|四五十|五六十|六七十|七八十|八九十)([ 　]*(?:亿元|万元|公里|千米|厘米|平方米|千克|公斤|小时|分钟|个人|元|人|名|位|个|岁|年|月|日|天|米|斤|克|吨|次|台|辆|本|件)?[ 　]*)(左右|上下)(?!划|移动|摇|摆|晃|浮|跳|走|看|张望|转|翻|起伏|震动|颠簸|滑|游|飞|跑|滚|上下班|班|文|铺|楼|车|床|台|手|脚|眼|打量|扫视|观察|攀爬|穿梭|升降|下沉|下降|上升|落|沉|坠)(?=$|[的，,。；;！？!?：:\\n])", new String[][]{{null, "", "重复啰嗦"}});

            // 只保留需要跨词/跨字泛化的语病规则；固定短词替换交给错词库。
            // “多/余/来/几”等已经表示约数，再叠加“左右/上下”属于重复限定。
            // 中间允许跨过“个、人、岁、名、位、公里”等短数量单位，因此“20多个人左右”也能覆盖。
            addRule("([0-9一二两三四五六七八九十百千万亿]+(?:多|余|来)|[0-9]+几|[一二两三四五六七八九]十几)([ 　]*(?:亿元|万元|公里|千米|厘米|平方米|千克|公斤|小时|分钟|个人|元|人|名|位|个|岁|年|月|日|天|米|斤|克|吨|次|台|辆|本|件)?[ 　]*)(左右|上下)(?!划|移动|摇|摆|晃|浮|跳|走|看|张望|转|翻|起伏|震动|颠簸|滑|游|飞|跑|滚|上下班|班|文|铺|楼|车|床|台|手|脚|眼|打量|扫视|观察|攀爬|穿梭|升降|下沉|下降|上升|落|沉|坠)(?=$|[的，,。；;！？!?：:\\n])", new String[][]{{null, "", "重复啰嗦"}});
            // “约/大约/大概/将近/接近 + 数字 + 多/余/来”：双重约数，只保留一种约数标记。
            addRule("(约|大约|大概|将近|接近)([ 　]*[0-9一二两三四五六七八九十百千万亿两零〇]+[ 　]*)(多|余|来)(?=[个人名位只条头匹辆部台口尾座把本次场局件张岁年月日天小时分钟秒米公里斤公斤千克克吨亩公顷元万元亿元%％度])", new String[][]{{"", null, "重复啰嗦"}});
            // “大概/大约/约（是/有）近/接近/将近 + 数字”：两个近似标记叠加，删除后一个。
            addRule("(大概|大约|约)([ 　]*(?:是|有)?[ 　]*)(近|接近|将近)(?=[ 　]*[0-9一二两三四五六七八九十百千万亿两零〇])", new String[][]{{null, "", "重复啰嗦"}});
            // “约/近/将近/差不多 + 明确数字 + 单位 + 左右/上下”：要求中间出现数字，降低“近”的词义歧义。
            addRule("(约|将近|差不多|(?<!附)近)([ 　]*[0-9零〇一二两三四五六七八九十百千万亿]+(?:\\.[0-9]+)?[ 　]*(?:亿元|万元|亿|万|千|平方公里|平方米|立方米|公里|千米|厘米|毫米|千克|公斤|小时|分钟|个人|个月|岁|元|人|名|位|个|天|年|月|日|米|吨|斤|克|次|台|辆|本|件|层|楼|%|％)?(?:出头)?[ 　]*)(左右|上下)(?=$|[的，,。；;！？!?：:\\n])", new String[][]{{null, "", "重复啰嗦"}});

            // “不少于/不低于……以上”及“不超过/不高于……以内/以下”：上下限表达重复；要求中间明确出现数字。
            addRule("(不少于|不低于)([^，,。；;！？!?：:\n]{0,12}?[0-9一二两三四五六七八九十百千万亿两]+[^，,。；;！？!?：:\n]{0,8}?)(以上)(?=[，,。；;！？!?：:\n]|$)", new String[][]{{null, "", "重复啰嗦"}});
            addRule("(不超过|不高于|至多)([^，,。；;！？!?：:\n]{0,12}?[0-9一二两三四五六七八九十百千万亿两]+[^，,。；;！？!?：:\n]{0,8}?)(以内|以下)(?=[，,。；;！？!?：:\n]|$)", new String[][]{{null, "", "重复啰嗦"}});
            // “云集了……名/位/人……参加”：要求出现明确的人数/人员量词，并在“参加”处收束分句。
            addRule("(云集(?:了)?)([^，,。；;！？!?：:\n]{0,24}?[0-9一二两三四五六七八九十百千万几两]+(?:多|余|来)?(?:名|位|人)[^，,。；;！？!?：:\n]{0,8}?)(参加(?:了)?)(?=[，,。；;！？!?：:\n]|$)", new String[][]{{null, "", "句式杂糅"}});

            // “分为/分成……部分组成(构成)”：两套构成句式杂糅。
            addRule("(分为|分成)([^由，。；！？\\n]{1,30}?)(部分(?:所)?(?:组成|构成))(?=[，。；！？、\\n的]|$)", new String[][]{{null, "部分", "句式杂糅"}});
            // “包括/包含……组成(构成)”：要求中间明确出现“数量+结构单位”，并在分句末收束，避免把“蛋白质的组成”等名词结构误判。
            addRule("(包括|包含)([^，,。；;！？!?：:\\n]{0,30}?(?:[0-9一二两三四五六七八九十百千万几两]+|若干|数个|多个|若干个)(?:个|项|类|种)?[^，,。；;！？!?：:\\n]{0,10}?(?:部分|模块|方面|环节|阶段|要素|因素|成分|元素|成员|项目|类别|类型|内容))([ 　]*(?:所)?(?:组成|构成))(?=[，,。；;！？!?：:\\n]|$)", new String[][]{{null, "", "句式杂糅"}});
            // “根据/依据/据 + 信息源 + 显示/表明……”：两套引述句式杂糅；只在信息源明确且谓语收束分句时处理。
            String evidenceSource = "调查|研究|统计|数据|资料|报告|监测|测算|实验|分析|结果|图表|报道|通报|公告|问卷|普查|专家|学者|机构|实际|情况|状况|现实|现状|形势|经验|常识";
            // “根据数据显示看 / 根据调查表明来看”：统一成“从……来看”。
            addRule("(?<![\u4E00-\u9FFFA-Za-z0-9])(根据|依据|据)([^，,。；;！？!?：:\n]{0,28}?(?:" + evidenceSource + "))([ 　]*(?:显示|表明)(?:来)?看)(?=[，,。；;！？!?：:\n]|$)", new String[][]{{"从", "来看", "句式杂糅"}});
            // “根据目前情况来看 / 依据数据看”：统一成“从……来看/看”。
            addRule("(?<![\u4E00-\u9FFFA-Za-z0-9])(根据|依据|据)([^，,。；;！？!?：:\n]{0,28}?(?:" + evidenceSource + "))([ 　]*(?:来)?看)(?=[，,。；;！？!?：:\n]|$)", new String[][]{{"从", null, "句式杂糅"}});
            addRule("(?<![\u4E00-\u9FFFA-Za-z0-9])(根据|依据|据)([^，,。；;！？!?：:\n]{0,28}?(?:" + evidenceSource + "))([ 　]*(?:显示|表明))(?=[，,。；;！？!?：:\n]|$)", new String[][]{{"", null, "句式杂糅"}});
            // “通过调查/研究/数据分析……显示/表明”：句首“通过……”与“……显示”杂糅；限定到信息源并收束分句。
            addRule("(?<![\u4E00-\u9FFFA-Za-z0-9])(通过)([^，,。；;！？!?：:\\n]{0,28}?(?:" + evidenceSource + "))([ 　]*(?:显示|表明))(?=[，,。；;！？!?：:\\n]|$)", new String[][]{{"", null, "句首句式杂糅"}});
            // “是由于/是因为……导致的(造成的/引起的)”：改为“是由……导致/造成/引起的”。
            // 2026-10 回归修复：“是由于X引起的”完全合法，仅“X所导致的”才是杂糅；原先把25处合法句改成“是由”。
            addRule("(是由于|是因为)([^，,。；;！？!?：:\n]{1,28}?)(所导致的|所造成的|所引起的|所决定的)(?=[，,。；;！？!?：:\n]|$)", new String[][]{{"是由", null, "句式杂糅"}});
            // 其他跨词句式杂糅，均收紧到分句边界，优先控制误报。
            addRule("((?<!在)受)([^，,。；;！？!?：:\\n]{1,24}?影响)(下)(?=[，,。；;！？!?：:\\n]|$)", new String[][]{{null, "", "句式杂糅"}});
            addRule("(对于)([^，,。；;！？!?：:\\n]{1,16}?)(看来)(?=[，,。；;！？!?：:\\n]|$)", new String[][]{{"在", null, "“对于……看来”应改为“在……看来”或“对于……来说”"}});
            addRule("(对)([^，,。；;！？!?：:\\n]{1,20}?)(没有引起重视)(?=[，,。；;！？!?：:\\n]|$)", new String[][]{{null, "没有重视", "句式杂糅"}});
            addRule("(对)([^，,。；;！？!?：:\\n]{1,20}?)(没引起重视)(?=[，,。；;！？!?：:\\n]|$)", new String[][]{{null, "没重视", "句式杂糅"}});
            addRule("(对)([^，,。；;！？!?：:\\n]{1,20}?)(未引起重视)(?=[，,。；;！？!?：:\\n]|$)", new String[][]{{null, "未重视", "句式杂糅"}});
            addRule("(听到|听见)([^，,。；;！？!?：:\\n]{1,24}?的消息)(传来)(?=[，,。；;！？!?：:\\n]|$)", new String[][]{{null, "", "句式杂糅"}});
            // “比……相比”需要跨越比较对象；排除“比赛/比较/比例”等普通词。
            addRule("(比)(?!赛|较|例|如|方|值|率|重|特|照|喻|拟|邻|丘|翼|目|肩|及|附|索)([^，,。；;！？!?：:\\n]{1,20}?)(相比)", new String[][]{{"与", null, "句式杂糅"}, {null, "", "句式杂糅"}});

            // 更多公开病句资料中反复出现的跨词句式；都要求明确结构或分句边界。
            // “根据……实际/情况/条件出发”：可改“从……出发”或仅保留“根据……”。
            addRule("(?<![\u4E00-\u9FFFA-Za-z0-9])(根据|依据)([^，,。；;！？!?：:\n]{1,24}?(?:实际|情况|状况|条件|特点|现实|现状))([ 　]*出发)(?=[，,。；;！？!?：:\n]|$)", new String[][]{{"从", null, "句式杂糅"}, {null, "", "句式杂糅"}});
            // “来源……来自/源自”：保留“来源”作中心词，统一把后面的“来自/源自”改成“是”，避免“资金的来源来自于……”随机生成坏句。
            addRule("(来源)([ 　]*(?:主要|只能|均|都|全部|大多|一般|往往|通常)?[ 　]*)(来自于?|源自于?)", new String[][]{{null, "是", "重复啰嗦"}});
            // “来源是来自/源自……”：已有“是”时直接删除后面的“来自/源自”。
            addRule("(来源(?:主要|均|都|全部|大多|一般|往往|通常)?是)([ 　]*)(来自于?|源自于?)", new String[][]{{null, "", "“来源是……”后不再叠加“来自/源自”"}});
            // “最好……比较合适”：只在“比较合适”收束分句时处理，不碰“比较合适的方案”。
            addRule("(最好)([^，,。；;！？!?：:\n]{1,24}?)(比较合适)(?=[，,。；;！？!?：:\n]|$)", new String[][]{{null, "", "句式杂糅"}, {"", null, "句式杂糅"}});
            // “是受……影响造成/导致/引起的”：把两套因果句式统一成“是由……造成/导致/引起的”。
            addRule("(是受)([^，,。；;！？!?：:\n]{1,24}?)(?:的)?影响(?:所)?(造成的|导致的|引起的)(?=[，,。；;！？!?：:\n]|$)", new String[][]{{"是由", null, "句式杂糅"}});
            // “作者是由……写成/撰写/创作的”：限定到分句末，避免修饰后续名词时误报。
            addRule("(作者是由)([^，,。；;！？!?：:\n]{1,24}?)(写成的|撰写的|创作的)(?=[，,。；;！？!?：:\n]|$)", new String[][]{{"作者是", "", "句式杂糅"}});
            // “采用的是以……为准”：只有“为准”到达分句边界才触发。
            addRule("(采用的是)([ 　]*以[^，,。；;！？!?：:\n]{1,24}?)(为准)(?=[，,。；;！？!?：:\n]|$)", new String[][]{{"", null, "句式杂糅"}});

            // “付出/付出了……为代价”：两套代价句式杂糅；只在“为代价”收束分句时删除后缀。
            // 2026-10 回归修复：“付出了……作为代价”中“作”被留下形成“生命作”残句，现把“作为代价”整体纳入删除组。
            addRule("(付出(?:了)?)([^，,。；;！？!?：:\n]{1,24}?)(作为代价|做为代价|为代价)(?=[，,。；;！？!?：:\n]|$)", new String[][]{{null, "", "句式杂糅"}});
            // “这要看/要看……所决定的”：保留“要看……”句式，删除后面重复的“所决定的”。
            addRule("(这要看)([^，,。；;！？!?：:\n]{1,30}?)(所决定的)(?=[，,。；;！？!?：:\n]|$)", new String[][]{{null, "", "句式杂糅"}});
            // “原因是……共同/综合/相互作用的结果”：保留“原因是……作用”，去掉重复的“结果”。
            addRule("((?:主要|根本)?原因(?:主要)?是)([^，,。；;！？!?：:\n]{1,30}?(?:共同|综合|相互)?作用)(的结果)(?=[，,。；;！？!?：:\n]|$)", new String[][]{{null, "", "句式杂糅"}});
            // “高达……之巨”：要求明确数值/约数及常见计量单位，避免泛化到普通“之巨”结构。
            addRule("(高达)([ 　]*(?:[0-9]+(?:\\.[0-9]+)?|[一二两三四五六七八九十百千万亿两数几]+)(?:多|余|来)?[ 　]*(?:元|万元|亿元|人|名|位|个|件|项|例|起|次|家|户|吨|千克|公斤|克|米|公里|平方米|平方公里|亩|公顷|年|月|天|小时|分钟|秒|%|％))([ 　]*(?:之巨|之多))(?=[，,。；;！？!?：:\n]|$)", new String[][]{{null, "", "重复啰嗦"}});

            addRule("(原因是)((?!由)[^，,。；;！？!?：:\n]{1,28}?)(所?造成的|所?导致的|所?引起的|造成|导致|引起)(?=[，,。；;！？!?：:\n]|$)", new String[][]{{null, "", "句式杂糅"}});
            addRule("(是因为)([^，,。；;！？!?：:、\\n]{1,15}?)(的原因)", new String[][]{{null, ""}, {"", null}});
            addRule("(围绕(?:[ 　]*以)?)([^，,。；;！？!?：:\\n]{1,24}?)(为中心)(?=[，,。；;！？!?：:\\n]|$)", new String[][]{{"以", null, "句式杂糅"}});
            addRule("(围绕(?:[ 　]*以)?)([^，,。；;！？!?：:\\n]{1,24}?)(为主题)(?=[，,。；;！？!?：:\\n]|$)", new String[][]{{"以", null, "句式杂糅"}});
            addRule("(围绕(?:[ 　]*以)?)([^，,。；;！？!?：:\\n]{1,24}?)(为核心|为目标)(?=[，,。；;！？!?：:\\n]|$)", new String[][]{{"以", null, "句式杂糅"}});
            addRule("(从(?:[ 　]*以)?)([^，,。；;！？!?：:\\n]{1,24}?)(为出发点)(?=[，,。；;！？!?：:\\n]|$)", new String[][]{{"以", null, "句式杂糅"}});
            addRule("(打着(?:[ 　]*以)?)([^，,。；;！？!?：:\\n]{1,24}?)(为幌子)(?=[，,。；;！？!?：:\\n]|$)", new String[][]{{"以", null, "句式杂糅"}});
            addRule("(借着(?:[ 　]*以)?)([^，,。；;！？!?：:\\n]{1,24}?)(为名义)(?=[，,。；;！？!?：:\\n]|$)", new String[][]{{"以", null, "句式杂糅"}});
            addRule("(借口(?:[ 　]*以)?)([^，,。；;！？!?：:\\n]{1,24}?)(为名)(?=[，,。；;！？!?：:\\n]|$)", new String[][]{{"以", null, "句式杂糅"}});
            addRule("(为了(?:[ 　]*以)?)([^，,。；;！？!?：:\\n]{1,24}?)(为目的)(?=[，,。；;！？!?：:\\n]|$)", new String[][]{{"以", null, "句式杂糅"}});
            addRule("(旨在(?:[ 　]*以)?)([^，,。；;！？!?：:\\n]{1,24}?)(为目的)(?=[，,。；;！？!?：:\\n]|$)", new String[][]{{"以", null, "句式杂糅"}});
            addRule("(本着(?:[ 　]*以)?)([^，,。；;！？!?：:\\n]{1,24}?)(为原则)(?=[，,。；;！？!?：:\\n]|$)", new String[][]{{"以", null, "句式杂糅"}});
            // “本着……为宗旨/为目的”：两套句式杂糅，统一为“以……为宗旨/目的”。
            addRule("(本着(?:[ 　]*以)?)([^，,。；;！？!?：:\\n]{1,24}?)(为宗旨|为目的)(?=[，,。；;！？!?：:\\n]|$)", new String[][]{{"以", null, "句式杂糅"}});
            // “根据/依据……为基础”：把“根据/依据……”与“以……为基础”两套结构统一。
            addRule("(根据|依据)([^，,。；;！？!?：:\\n]{1,28}?)(为基础)(?=[，,。；;！？!?：:\\n]|$|进行|开展|建立|制定|设计|构建|分析|研究|开发|计算|判断|推导|讨论|实施|推进|工作|处理|形成|提出|调整|改进|优化|编制|规划|建设)", new String[][]{{"以", null, "句式杂糅"}});
            // “基于……（的）基础上”：前后重复表达“以……为基础”，改为“在……（的）基础上”。
            addRule("(基于)([^，,。；;！？!?：:\\n]{1,28}?)(的?基础上)", new String[][]{{"在", null, "重复啰嗦"}});
            // “归咎于……的原因”：归咎于本身已经表达原因归属，分句末删除重复“的原因”。
            addRule("(归咎于)([^，,。；;！？!?：:\\n]{1,24}?)(的原因)(?=[，,。；;！？!?：:\\n]|$)", new String[][]{{null, "", "重复啰嗦"}});
            // “在于……而造成/导致/引起的”：两套因果句式杂糅；仅在分句末触发。
            addRule("(在于)([^，,。；;！？!?：:\\n]{1,28}?)(而(?:造成|导致|引起)的)(?=[，,。；;！？!?：:\\n]|$)", new String[][]{{null, "", "句式杂糅"}});
            addRule("(对于)([^，,。；;！？!?：:\\n]{1,20}?)(问题上)(?=[，,。；;！？!?：:\\n]|$)", new String[][]{{"在", null, "句式杂糅"}, {null, "问题", "句式杂糅"}});
            addRule("(经过)([^，,。；;！？!?：:\\n]{1,24}?(?:努力|讨论|研究|调查|考虑|协商|学习|训练|治疗|处理|改革|建设|实践|尝试|试验|实验|检查|审核|审查|指导|帮助|教育|培养|锻炼|改进|调整|修改|优化|整顿|治理|管理))([ 　]*下)(?=[，,。；;！？!?：:\\n]|$)", new String[][]{{null, "", "句式杂糅"}});
            addRule("(由于)([^，,。；;！？!?：:\\n]{1,24}?(?:影响|作用|帮助|指导|领导|支持|压力|条件|环境|背景|形势|情况下))([ 　]*下)(?=[，,。；;！？!?：:\\n]|$)", new String[][]{{"在", null, "句式杂糅"}});
            addRule("(目的是)( *)(为了)", new String[][]{{"是", null}, {null, ""}});
            addRule("((?:大多|主要|大都|基本|基本上)(?:是)?以)([^，。；！？、\n]{1,20}?)(为主)", new String[][]{{"以", null, "句式杂糅"}});
            addRule("(有)([^，,。；;！？!?：:\\n]{0,24}?(?:[0-9一二两三四五六七八九十百千万几两]+|若干|数个|多个|若干个)(?:个|项|类|种)?[^，,。；;！？!?：:\\n]{0,10}?(?:部分|模块|方面|环节|阶段|要素|因素|成分|元素|成员|项目|类别|类型|内容))([ 　]*(?:组成|构成))(?=[，,。；;！？!?：:\\n]|$)", new String[][]{{"由", null, "搭配不当"}});
            addRule("(深受)([^，,。；;！？!?：:、\\n]{0,10}?)(所)(?=喜爱|欢迎|爱戴|好评|青睐|瞩目)", new String[][]{{null, ""}});
            addRule("(最高|最低|最多|最少)((?:有|是|为|达到)?[ 　]*[0-9零〇一二两三四五六七八九十百千万亿]+(?:\\.[0-9]+)?[ 　]*(?:亿元|万元|亿|万|千|平方公里|平方米|立方米|公里|千米|厘米|毫米|千克|公斤|小时|分钟|个人|岁|元|人|名|位|个|天|年|月|日|米|吨|斤|克|次|台|辆|本|件|层|楼|%|％)?[ 　]*)(以上|以下|左右|上下)(?=$|[的，,。；;！？!?：:\\n])", new String[][]{{null, ""}});
            addRule("(关键在于|关键是)([^。！？\\n]{1,20}?)(是十分重要的|是很重要的|起到重要作用|决定性的)", new String[][]{{"", null}, {null, ""}});
            // 2026-10 回归修复：排除逗号冒号，避免“……避免接触放射性物质,尽量不要做X线片”跨分句误删“不要”造成语义反转。
            addRule("(切忌)([^，,。；！？、：:\\n]{1,15}?)(不要|不可)", new String[][]{{"千万", null}, {null, ""}});
            addRule("(避免|防止|严防)([^，,。；！？、：:\\n]{1,15}?)(不要)(?!脸|命|紧)", new String[][]{{null, ""}});
            addRule("(防止)([ 　]*(?:事故|交通事故|火灾|悲剧|灾难|类似事故|类似事件|此类事件|同类事件)[ 　]*)(不再)(?=[ 　]*发生)", new String[][]{{null, "再次"}});

            addRule("(令人|让人|叫人)( *)(堪忧)", new String[][]{{"", null}, {null, "担忧"}});
            addRule("(首当其冲)(的? *)(问题|任务|事情|要务|条件)", new String[][]{{"首要", null}, {"最重要", null}});
            addRule("(改善|改变|加强)([^，,。；;！？!?：:、\\n]{0,8}?)(水平|素养)", new String[][]{{"提高", null}});
            addRule("(加快|加速)([^，,。；;！？!?：:、\\n]{0,8}?)(效率)", new String[][]{{"提高", null}});
            addRule("(缓解|减缓)([^，,。；;！？!?：:、\\n]{0,8}?)(态度|立场)", new String[][]{{"缓和", null}});
            addRule("(悬殊)( *)(很大|极大|特别大|非常大)", new String[][]{{null, ""}, {"差距", null}});
            addRule("(?<![\u4E00-\u9FFFA-Za-z0-9])(通过)([^，,。；;！？!?：:\\n]{1,24}?)([，,][ 　]*使)(?!用|得|劲|坏|命|绊|眼|性|气|然)", new String[][]{{null, "，", "仅处理带逗号的典型“通过……，使……”主语残缺，改为“通过……，主语……”结构"}});
            addRule("(令人|让人|叫人)( *)(贻笑大方)", new String[][]{{"", null}});
            addRule("(凯旋)( *)(而归)", new String[][]{{null, ""}});
            addRule("(可以|能够)( *)(堪称)", new String[][]{{"", null}});
            addRule("(突然|顿时|一下子)( *)(恍然大悟|豁然开朗)", new String[][]{{"", null}});

            // “忍俊不禁”本身已经包含“忍不住发笑”的意思。
            // 第一层仅处理句尾/停顿前可以完整确认的重复笑语，直接连同“的地得做作”一起删除。
            addRule("(忍俊不禁)()([的地得]?[ 　]*(?:笑出了声音|笑出了声|笑出声音|笑出声来|笑出声|笑得前仰后合|笑得合不拢嘴|笑得直不起腰|笑得停不下来|笑到前仰后合|笑到直不起腰|笑了起来|笑起来|笑了笑|笑个不停|笑不停|发笑起来|发笑了|发笑|笑了|笑着|笑)[ 　]*)(?=[，,。；;！？!?：:、…\n]|$)", new String[][]{{null, "", "语义重复"}});
            // 第二层遇到“说、问、看、转身”等后续动作时，只删除明确重复的笑语，不吞掉后面的动作。
            // 中间的“的/地/得/做/作”保留，之后仍可交给“的地得做作”模型判断，避免把句法一起破坏。
            addRule("(忍俊不禁)([的地得]?[ 　]*)(笑了起来|笑起来|笑了笑|发笑起来|发笑了|发笑|笑了|笑着|笑)(?=[ 　]*(?:对着|朝着|向着|跟着|说道|问道|答道|喊道|叫道|骂道|叹道|说|道|问|答|回答|解释|补充|提醒|告诉|喊|叫|骂|叹|讲|谈|对|朝|向|跟|一边|边|又|还|看向|望向|走向|跑向|看|望|瞧|盯|转身|回头|走|跑|坐|站|起身|低头|抬头|点头|摇头|伸手|抬手|挥手|拍|拿|放|递|推|拉|抱|继续|接着|随后|开口))", new String[][]{{null, "", "语义重复"}});

            addRule("(难言之隐)(的? *)(苦衷|事情|原因)", new String[][]{{null, ""}});
            addRule("(责无旁贷)(的? *)(责任|义务)", new String[][]{{null, ""}});
            addRule("(真知灼见)(的? *)(意见|看法|见解)", new String[][]{{null, ""}});
            addRule("(至少|起码|最少)([^，。；！？、\n]{1,15}?)(以上)", new String[][]{{null, "", "重复啰嗦"}, {"", null, "重复啰嗦"}});

            // pycorrector 的经典示例包含“因该→应该、让坐→让座”，但本应用不做无条件替换：
            // “因该公司/因该项目”以及“这里不让坐/让他坐下”都可能是正常表达，只在高确定性上下文触发。
            addRule("(因该)()((?=为|是|已经|正在|尽快|尽量|及时|立即|马上|首先|先(?:行|把|做|去|来|看|说|处理|解决|完成)))", new String[][]{{"应该", null, "用字不当"}});
            addRule("(看在)([^，,。；;！？!?：:\\n]{1,40}?的)(份上)", new String[][]{{null, "分上", "规范写法为‘看在……的分上’"}});
            addRule("((?:第?(?:[0-9零〇一二两三四五六七八九十百千万亿]+(?:余|多|来)?|几)|数|多|若干)[ 　]*)()(位)(?=[ 　]*(?:犯罪嫌疑人|嫌疑人|犯罪分子|罪犯|犯人|嫌犯|逃犯|通缉犯|凶手|歹徒|人贩子|毒贩|诈骗犯|盗窃犯|抢劫犯|杀人犯)(?=[ 　]*(?:$|[，,。；;！？!?：:、…\n]|已|被|因|涉嫌|正在|正|曾|将|均|都|分别|目前|当场|随后|后来|最终|供述|交代|承认|落网|被捕|抓获|归案|接受|进入|面临|受到|遭到|逃跑|作案|参与|实施|和|与|及|以及|中|等)))", new String[][]{{null, "名", "“位”不宜用于嫌疑人等负面身份人物"}});
            addRule("(开心|快乐|高兴|欢快|兴奋|愉快|轻快|小心|小心翼翼|慢慢|缓缓|艰难|吃力|谨慎|悠闲)([ 　]*)([的地得](?:淌水|蹚水))", new String[][]{{null, "地蹚水", ""}});
            addRule("(淌水)()((?=过(?:河|江|溪|沟|水坑|积水|浅滩)|而过|过去|前行|行走|通过|赶路|救人|转移|巡查|巡逻|撤离|上岸|下田|玩(?:水)?))", new String[][]{{"蹚水", null, "人从水中行走应用“蹚水”；“淌”表示液体流动"}});
            addRule("(不止)(是[^，,。；;！？!?：:\\n]{1,28}?[，,]?[ 　]*)(而且|并且|更|甚至|同时|又|也|还(?!有[ 　]*(?:[0-9零〇一二两三四五六七八九十百千万亿几数多]+)))", new String[][]{{"不只", null, ""}});
            String seatRecipient = "(?:[^，,。；;！？!?：:\\n]{0,10}?(?:老人|老年人|长者|孕妇|孩子|小孩|儿童|病人|患者|伤员|残疾人|乘客|客人|来宾|老师|同学|学生|朋友|长辈|父母|爸爸|妈妈|爷爷|奶奶|先生|女士|军人|工人|行人|路人|陌生人|他|她|你|您|他们|她们|大家|对方|别人|人|者|员|客|生|师|童|妇|士|友|辈))";
            addRule("((?:为|给|向)" + seatRecipient + ")([ 　]*让)(坐)(?=(?:了|过)?[吧吗呢啊呀哦嘛]?(?:[，,。；;！？!?：:、…\\n]|$))", new String[][]{{null, "座", ""}});

            // 参考 LanguageTool 中文量词规则：‘俩/仨’本身已带数量义，后接量词时改为‘两/三 + 量词’。
            String pairQuantifiers = "个|位|名|组|批|队|班|户|家|对|双|只|条|件|本|辆|台|间|座|所|头|匹|口|份|张|次|场|套|种|类|项|门|部";
            addRule("(俩)([ 　]*)(" + pairQuantifiers + ")", new String[][]{{"两", null, "数量表达不规范"}});
            addRule("(仨)([ 　]*)(" + pairQuantifiers + ")", new String[][]{{"三", null, "数量表达不规范"}});

            // GEC 2026: low-ambiguity collocation / classifier / redundancy / logic rules.
            addRule("(采纳)([ 　]*(?:了|过)?[ 　]*(?:(?:一系列|一整套|若干项|多项|数项|一项|两项|三项|四项|五项|几项|各种|各项|相关|有效|必要|具体|严格|重要|新的|最新|这些|那些|多种|不同|相应|针对性|科学|合理|综合|配套|强有力|有力|可行|切实可行|行之有效|比较有效|各类|一切|专项|应对|防范|预防|整改|保护|处罚|执法|监管|管理|改进|改革|治理|控制|防控|保障)(?:的)?[ 　]*){0,4})(措施)(?=$|[了的来后时，,。；;！？!?：:\\n])", new String[][]{{"采取", null, "搭配不当"}});
            addRule("(采取)([ 　]*(?:了|过)?[ 　]*(?:(?:(?:专家|顾问|群众|员工|领导|老师|同事|用户|客户|消费者|公众|家长|学生|律师|医生|团队|公司|部门|政府|学校|委员会|评委|他们|她|他|我|您|大家)(?:提出的|给出的|发表的|提供的|的)|(?:相关|合理|宝贵|具体|专业|建设性|中肯|可行|重要|详细|针对性|上述|这些|那些|有效|改进|整改|完善|管理|指导)(?:的)?)[ 　]*){0,3})(意见|建议)(?!后续|后备|后方)(?=$|[了的后，,。；;！？!?：:\\n])", new String[][]{{"采纳", null, "搭配不当"}});
            addRule("(增强)([ 　]*(?:了|过)?[ 　]*(?:(?:该|本|这个|那个|整个)?(?:公司|企业|学校|医院|部门|团队|单位|组织|集团|机构|系统|工厂|车间|项目|平台|班级|行业|领域|社会|员工|干部|学生|师生|职工|群众|居民|公民)(?:的)?[ 　]*)?(?:(?:整体|综合|实际|平均|运行|生产|工作|学习|处理|运输|物流|办公|管理|能源|办事|执行|行政|审核|办案|通关|服务|运营|审批|运转|劳动|业务|教学|科研|沟通|协作|加工|施工|生产经营|供应链|企业运营|企业生产|资源利用)?[ 　]*)?)(效率)(?=$|[的了后，,。；;！？!?：:\\n])", new String[][]{{"提高", null, "搭配不当"}});
            addRule("(加快|扩大)([ 　]*(?:了|过)?[ 　]*(?:(?:执法|打击|处罚|监管|检查|监督|治理|巡查|管理|惩治|处罚打击|监督检查|处罚监管|反腐|执纪|整改|整治|执法检查|查处|督查|追责|惩罚|惩戒|处罚执行)[ 　]*(?:的[ 　]*)?)?)(力度)(?=$|[的了后，,。；;！？!?：:\\n])", new String[][]{{"加大", null, "搭配不当"}});
            addRule("(提高)([ 　]*(?:了|过)?[ 　]*(?:执法|打击|处罚|监管|检查|监督|治理|巡查|管理|惩治|处罚打击|监督检查|处罚监管|反腐|执纪|整改|整治|执法检查|查处|督查|追责|惩罚|惩戒|处罚执行)[ 　]*(?:的[ 　]*)?)(力度)(?=$|[的了后，,。；;！？!?：:\\n])", new String[][]{{"加大", null, "搭配不当"}});
            addRule("(加大)([ 　]*(?:了|过)?[ 　]*(?:(?:该|本|这个|那个|整个)?(?:公司|企业|学校|医院|部门|团队|单位|组织|集团|机构|系统|工厂|车间|项目|平台|班级|行业|领域|社会|员工|干部|学生|师生|职工|群众|居民|公民)(?:的)?[ 　]*)?(?:(?:整体|综合|实际|平均|运行|生产|工作|学习|处理|运输|物流|办公|管理|能源|办事|执行|行政|审核|办案|通关|服务|运营|审批|运转|劳动|业务|教学|科研|沟通|协作|加工|施工|生产经营|供应链|企业运营|企业生产|资源利用)?[ 　]*)?)(效率)(?=$|[的了后，,。；;！？!?：:\\n])", new String[][]{{"提高", null, "搭配不当"}});
            addRule("(加大)([ 　]*(?:了|过)?[ 　]*(?:(?:该|本|这个|那个|整个)?(?:公司|企业|学校|医院|部门|团队|单位|组织|集团|机构|系统|工厂|车间|项目|平台|班级|行业|领域|社会|员工|干部|学生|师生|职工|群众|居民|公民)(?:的)?[ 　]*)?(?:环保|消防|安全|学习|守法|工作|服务|参与|健康|法律|自我保护|节能|创新|节约|公共|道德|合规|防范|自我管理|监督|治理|员工|公众|干部|群众|师生|个人|团队|社会|全体|集体|志愿者)?[ 　]*)(自觉性|主动性)(?=$|[的了后，,。；;！？!?：:\\n])", new String[][]{{"增强", null, "搭配不当"}});
            addRule("(损坏)([ 　]*(?:了|过)?[ 　]*(?:(?:消费者|用户|群众|他人|别人|企业|客户|公民|公众|公民个人|居民|员工|学生|国家|社会|广大群众|广大消费者|广大用户|人民群众|个人|自身|大家|我们|你们|他们|她们)(?:的)?[ 　]*)?(?:合法|切身|正当|根本|基本|经济|财产|公共|社会|集体|长远|个人|自身)?[ 　]*)(利益|权益)(?=$|[的了后，,。；;！？!?：:\\n])", new String[][]{{"损害", null, "搭配不当"}});
            addRule("(达到)([ 　]*(?:了|过)?[ 　]*(?:世界|全国|省级|市级|本届|年度|联赛|赛季)?[ 　]*)(冠军)(?=$|[了后，,。；;！？!?：:\\n])", new String[][]{{"获得", null, "搭配不当"}});
            addRule("((?:这|那|该|此|某|一|几|每|多|两|数)?(?:篇|份|部|本|则|段)?(?:系列)?(?:新闻报道|调查报告|研究报告|年度报告|分析报告|工作报告|数据报告|专题报道|专题报告|新闻稿|文学作品|影视作品|文艺作品|艺术作品|优秀作品|文学著作|影视剧|纪录片|电视剧|动画片|报告|文章|论文|作文|散文|小说|电影|影片|纪录|剧作|诗歌|作品|文献|资料|材料|数据|新闻|报道|专著|书籍|白皮书|调研|调查|访谈|研究|论述|图表|统计|纪录片))([ 　]*(?:(?:深刻(?:地)?|真实(?:地)?|如实(?:地)?|准确(?:地)?|客观(?:地)?|充分(?:地)?|全面(?:地)?|集中(?:地)?|清晰(?:地)?|鲜明(?:地)?|生动(?:地)?|直接|间接|深入(?:地)?|详细(?:地)?|较好(?:地)?|很好(?:地)?|直观(?:地)?|真实而深刻(?:地)?|不同程度地|在一定程度上|从不同角度|比较真实(?:地)?)[ 　]*){0,2})(反应)(?=[ 　]*(?:了|出了?|着)?[ 　]*(?:社会(?:生活|现状|现实|问题|矛盾|风貌|变化|需求|情况)?|时代(?:风貌|特征|背景|变化)?|现实(?:生活|情况|问题)?|生活(?:现状|困境|状态)?|民生|民情|民意|人性|人心|人们的|群众的|人民的|历史(?:事实|真相|变迁|情况)?|事实|真相|现象|问题|矛盾|弊端|状况|情况|形势|趋势|特点|特征|需求|心声|诉求|观点|态度|情绪|影响|成效|成果|变化|困难|困境|面貌|风貌|差异|实际))", new String[][]{{null, "反映"}});
            addRule("((?:当前|如今|现在|当下|目前|国内|全球|国际|世界|我国|本国|各国|欧洲|亚洲|本地|地方|区域|整体)?(?:经济|就业|国际|政治|安全|市场|国际政治|地区安全|国际安全|经济发展|经济增长|社会|社会经济|外交|外交安全|军事|金融|行业|企业经营|劳动就业|财政|治安|发展|外部经济|粮食安全|网络安全))([ 　]*)(形式)(?=[ 　]*(?:十分|非常|特别|较为|日益|相当|愈发|极其|越来越|比较|依然|仍然|持续|更加|格外|异常|严峻得令人担忧)?(?:严峻|不容乐观|紧张|复杂多变|扑朔迷离))", new String[][]{{null, "形势"}});
            addRule("(截止)([ 　]*)(昨日|昨天|前日|昨晚|昨夜|上周末|上个月底|去年底|上月底|去年年末|本月初|上周五|上周日|本月一日|今日|今天|年底|月底)(?=[ 　]*[，,]?[ 　]*(?:已|已经|共有|累计|目前|共计|合计|总计|达到|实现|完成|登记|统计|确认|发现|录得))", new String[][]{{"截至", null}});
            addRule("(?<=[一二两三四五六七八九十百千万几这那多少0-9])(头)([ \\u3000]*(?:(?:白色|黑色|白|黑|高大)(?:的)?[ \\u3000]*))(马)(?=$|[是也已正会能将，,。；;！？!?：:\\n])", new String[][]{{"匹", null, "搭配不当"}});
            addRule("(?<=[一二两三四五六七八九十百千万几这那多少0-9])(条|支)([ \\u3000]*(?:(?:白色|黑色|灰色|大|小)(?:的)?[ \\u3000]*)?)(天鹅|大白鹅|小白鹅|白鹅|黑鹅|灰鹅|鹅)(?=$|[是也已正会能将，,。；;！？!?：:\\n])", new String[][]{{"只", null, "搭配不当"}});
            addRule("(?<=[一二两三四五六七八九十百千万几这那多少0-9])(枚)([ \\u3000]*(?:(?:漂亮|鲜艳|红色|白色)(?:的)?[ \\u3000]*)?)(玫瑰花|菊花|百合花)(?=$|[是也已正会能将，,。；;！？!?：:\\n])", new String[][]{{"朵", null, "搭配不当"}});
            addRule("(?<=[一二两三四五六七八九十百千万几这那多少0-9])(片)([ \\u3000]*(?:(?:精彩|经典|好看)(?:的)?[ \\u3000]*)?)(电影|纪录片|影片|微电影)(?=$|[是也已正会能将，,。；;！？!?：:\\n])", new String[][]{{"部", null, "搭配不当"}});
            addRule("(?<=[一二两三四五六七八九十百千万几这那多少0-9])(间)([ \\u3000]*(?:(?:新建|漂亮|公立)(?:的)?[ \\u3000]*)?)(学校|大学|小学|中学)(?=$|[是也已正会能将，,。；;！？!?：:\\n])", new String[][]{{"所", null, "搭配不当"}});
            addRule("(?<=[一二两三四五六七八九十百千万几这那多少0-9])(匹)([ \\u3000]*(?:(?:凶猛|高大|大|小)(?:的)?[ \\u3000]*)?)(狮子|老虎)(?=$|[是也已正会能将，,。；;！？!?：:\\n])", new String[][]{{"头", null, "搭配不当"}});
            addRule("(?<=[一二两三四五六七八九十百千万几这那多少0-9])(颗)([ \\u3000]*(?:(?:高大|古老|茂盛|小)(?:的)?[ \\u3000]*)?)(松树|柏树|柳树|杨树|桃树|苹果树|榕树|梧桐树|枫树|树)(?=$|[是也已正会能将，,。；;！？!?：:\\n])", new String[][]{{"棵", null, "搭配不当"}});
            addRule("(?<=[一二两三四五六七八九十百千万几这那多少0-9])(把)([ \\u3000]*(?:(?:新买|干净)(?:的)?[ \\u3000]*)?)(裤子|长裤|短裤|牛仔裤)(?=$|[是也已正会能将，,。；;！？!?：:\\n])", new String[][]{{"条", null, "搭配不当"}});
            addRule("((?:每个|每位|每名|(?:[0-9]{1,4}|[一二两三四五六七八九十百千万零〇]{1,8}|几|若干)(?:个|名|位))[ 　]*(?:学生|老师|同学|职工|员工|工人|医生|护士|警察|司机|顾客|居民|旅客|观众|群众|记者|代表|志愿者|乘客|家长|青年|老人|专家|教授|学生代表|教师|职员|研究员|运动员|科研人员))()(们)(?=$|[都也和与是有各已在会能到来走去说做发讲，,。；;！？!?：:\\n])", new String[][]{{null, "", "语义重复"}});
            addRule("((?:是|成为|变成|被视为)[ 　]*(?:当前|眼下|目前|当下)?当务之急)()([ 　]*的工作)(?=$|[，,。；;！？!?：:\\n])", new String[][]{{null, "", "语义重复"}});
            addRule("((?:荣获|获得|取得)[^，,。；;！？!?：:\\n]{0,16}?殊荣)()([ 　]*称号)(?=$|[的，,。；;！？!?：:\\n])", new String[][]{{null, "", "语义重复"}});
            addRule("(无不)([ 　]*)(毫无例外(?:地)?)(?=[ 　]*(?:赞成|认为|喜欢|觉得|支持|参加|出席|感动|震惊|表示|感受|响应|为之))", new String[][]{{null, "", "语义重复"}});
            addRule("(之所以)([^，,。；;！？!?：:\\n]{2,36}?)(的原因)(?=[ 　]*(?:是|在于|就是))", new String[][]{{"", null, "句式杂糅"}});
            addRule("(经常性[地的]?)([ 　]*)(频频)(?=[ 　]*(?:发生|出现|发生事故|出错|犯错|出问题|出故障|发生问题|发作|上涨|下降|波动))", new String[][]{{"", null, "语义重复"}});
            addRule("(不约而同地)([ 　]*)(一致)(?=[ 　]*(?:同意|赞成|答应|表示同意))", new String[][]{{null, "", "语义重复"}});
            addRule("(预防)([ 　]*(?:交通事故|安全事故|事故|火灾事故|火灾|感染|疫情|问题|悲剧|灾难|意外事故|类似事件|此类事件|同类事件|此类问题|类似问题|泄露事件|泄密事件|校园欺凌|欺凌事件)[ 　]*)(不再)(?=[ 　]*发生)", new String[][]{{null, "再次"}});
            addRule("(杜绝)([ 　]*(?:交通事故|安全事故|事故|火灾事故|火灾|感染|疫情|问题|悲剧|灾难|意外事故|类似事件|此类事件|同类事件|此类问题|类似问题|泄露事件|泄密事件|校园欺凌|欺凌事件)[ 　]*)(不再)(?=[ 　]*发生)", new String[][]{{null, "再次"}});
            addRule("(遏制)([ 　]*(?:雾霾|恶劣天气|极端天气|污染天气|沙尘暴|扬沙天气)[ 　]*)(不)(?=[ 　]*(?:再)?频发)", new String[][]{{null, ""}});
            addRule("(落实)([ 　]*并[ 　]*)(制定)(?=[ 　]*(?:好|新的|本年度|年度|工作|全年|本年|下一年度|明年|新一轮|中长期)?(?:规划|计划|方案|制度|政策))", new String[][]{{"制定", "落实", "语序不当"}});
            addRule("((?:记者|媒体|报社|新闻记者|记者们|电视台|新闻媒体|广播电台|新闻机构|新闻中心|新闻网站|本报记者|编辑|通讯社|记者站|新闻主播|主持人)(?:在现场|刚刚|已经|曾经|专门|及时|详细|如实|客观地|全面)?)([ 　]*)(报到)(?=[ 　]*(?:了|过)?(?:这场比赛|此次活动|这一事件|这场事故|本次会议|这一新闻|这次赛事|这条新闻|此次事件|这件事|这起案件|这起事故|整个事件|此事|该事件|该案件|本次事件|这场赛事|本次展览|本次活动|这次展览))", new String[][]{{null, "报道"}});
            addRule("((?:经济|社会|制度|体制|行业|产业|经济结构|产业结构|组织结构|国家经济|企业|社会经济|整个行业)(?:转型|转轨|改革|调整|变革|改制|升级|改造)[ 　]*)()(过度)(?=[ 　]*(?:时期|阶段|期))", new String[][]{{null, "过渡"}});
            addRule("(过渡)([ 　]*)(消费|依赖|医疗)(?=$|[的了使让会易致，,。；;！？!?：:\\n]|(?:现象|问题|行为|造成|导致|现状))", new String[][]{{"过度", null}});
            addRule("(接待)([ 　]*(?:了|过)?[ 　]*)(来信)(?=$|[，,。；;！？!?：:\\n])", new String[][]{{"处理", null, "搭配不当"}});
            addRule("((?:群众|居民|市民|家长|学生|员工|职工|老师|教师|网友|消费者|用户|旅客|乘客|患者|病人|业主|代表|记者|朋友|同学|群众代表|市民代表|家长代表|学生代表|业主代表))([ 　]*(?:已|已经|曾|多次|先后)?[ 　]*向[ 　]*(?:政府|有关部门|部门|领导|学校|校方|老师|医生|客服|平台|公司|物业|工作人员|负责人|主管|媒体|单位|社区|街道|监管部门|教育部门)[ 　]*)(反应)(?=[ 　]*(?:了|过)?[ 　]*(?:问题|情况|意见|建议|困难|诉求|需求|民意|线索|现象|隐患|真实情况|具体情况|实际情况|相关情况|相关问题|投诉|不满|生活问题|质量问题))", new String[][]{{null, "反映"}});
            addRule("(?<![\\u4e00-\\u9fffA-Za-z0-9])(截止)([ 　]*)((?:(?:20[0-9]{2}|19[0-9]{2})年(?:[0-9]{1,2}|[一二三四五六七八九十]+)月(?:[0-9]{1,2}|[一二三四五六七八九十]+)日|(?:[0-9]{1,2}|[一二三四五六七八九十]+)月(?:[0-9]{1,2}|[一二三四五六七八九十]+)日))(?=[ 　]*[，,][ 　]*(?:已|已经|累计|目前|共有|共计|合计|总计|共|达到|实现|完成|登记|统计|确认|发现|录得))", new String[][]{{"截至", null}});
            // Chinese conditional correction; context restrictions based on LanguageTool zh rules.
            // Only matched grammar spans are changed; fixed typo replacements stay in 错别字.txt.
            addRule("(?<![第零〇一二两三四五六七八九十百千万亿0-9A-Za-z])(二)()((?:个(?=孩子|人|苹果|问题|办法|包子))|(?:本(?=书|小说|教材|杂志|漫画|字典))|(?:部(?=电影|电视剧|小说|作品))|(?:辆(?=车|汽车|自行车|卡车|轿车))|(?:只(?=猫|狗|鸟|鸡|鸭|鹅|兔子))|(?:张(?=桌子|纸|照片|车票|门票))|(?:台(?=电脑|电视|机器|设备)))", new String[][]{{"两", null}});
            // “二三天”与“两三天”均可表达约数，不自动统一字面形式。
            addRule("(被)([ 　]*(?:大家|同学们|同事们|老师们|选民|代表们|股东|股东们|董事会|委员会|评委|网友们|学生们|人们)[ 　]*)(当选为)(?=[^，,。；;！？!?：:\\n]{1,16}(?:[，,。；;！？!?：:\\n]|$))", new String[][]{{null, "选为", "搭配不当"}});
            addRule("(由)([ 　]*(?:他|她|他们|她们|大家|我们|你们|负责人|领导|班长|队长|老师|经理|校长|主席|主任|委员|将军|首领|组长|代表|专家|成员|学生|学者)(?:等人)?[ 　]*)(为首)(?=的)", new String[][]{{"以", null, "句式杂糅"}});
            addRule("(?<=[一二两三四五六七八九十几这那])(片)([ \\u3000]*(?:(?:精彩|优秀|重要|著名|学术|长篇|短篇)(?:的)?[ \\u3000]*)?)(文章|论文|作文|散文|报告)(?=$|[的了呀呢吧。，,；;！？!?:：\\n])", new String[][]{{"篇", null, "搭配不当"}});
            addRule("(?<=[一二两三四五六七八九十几这那])(所)([ \\u3000]*(?:(?:明亮|宽敞|漂亮|干净|大|小)(?:的)?[ \\u3000]*)?)(教室|卧室|厨房|厕所|浴室|客厅)(?=$|(?:很|又|真|挺|非常)|[的里内中是也。，,；;！？!?：\\n])", new String[][]{{"间", null, "搭配不当"}});
            addRule("(必需)([ 　]*(?:(?:认真|仔细|及时|尽快|按时|立即|马上|优先|主动|全面|共同|先|再|继续|逐步|严格|切实|尽早|如期|妥善)[ 　]*)?)((?:完成|参加|检查|遵守|学习|处理|解决|说明|办理|提交|回答|执行|落实|及时报告|报告|履行|支付|缴纳|整改|复核|复查|准备|整理|保存|核实|确认|维修|修复|修改|更新|联系|负责|照顾|保护|承担|遵循|接受|通过|结束|开始|提高|降低|改进|加强|开展|启动|继续|停止|主动配合|配合|按时归还|归还|认真阅读|阅读))(?!品|率|度|量|物|件|用品|器具|品种)", new String[][]{{"必须", null}});
            // 鸡鸭鹅及常见鸟类用“只”计数；要求前一字符明确是数字，且鸟名后立即到语法边界，
            // 因此“三条鸡腿”“三条孔雀鱼”不会被误改。
            addRule("(?<=[0-9一二两三四五六七八九十百千万几某])([条支])([ 　]*)(鸭子|鸡|鹅|鸽子|麻雀|喜鹊|乌鸦|鹦鹉|燕子|天鹅|孔雀|蝴蝶)(?=[的了着过是在被把让给对和与同或就也都还很太真会能可要想走跑跳飞游吃喝咬叫哭笑我看你他她它们这那正将已曾又并而却才便则，,。；;！？!?：:、…\\n]|$)", new String[][]{{"只", null, ""}});

            // 参考 LanguageTool 的动宾搭配思路，但只处理中心词明确且到边界的高确定性结构。
            // ‘执行义务/职责/承诺/诺言’统一为‘履行……’，不会碰‘执行义务教育政策’这类后面仍有中心词的正常表达。
            addRule("(执行)(了?[^，,。；;！？!?：:\\n]{0,12}?)(义务|职责|承诺|诺言)(?=[了着过的所，,。；;！？!?：:、…\\n]|$)", new String[][]{{"履行", null, "搭配不当"}});

            // 标点高精度规则：只处理规范边界明确的场景，宁可漏改也不误改。
            // 并列项末尾带“啊、呀、呢、啦、哇、嘛、吧、呐”等语气助词时，
            // 这些成分已不是简单词语并列，项间应用逗号而不是顿号。
            // 2026-10 回归修复：“餐厅、酒吧、网吧”等以“吧”结尾的场所名词不是语气助词项，排除常见“X吧”名词。
            String particleListItem = "[\\u4E00-\\u9FFFA-Za-z0-9]{1,12}(?:[啊呀呢啦哇嘛呐]|(?<!网|酒|书|氧|水|画|影|音|陶|咖|餐|玩|桌|聊|唱)吧)";
            addRule("(" + particleListItem + ")([ 　]*)(、)(?=[ 　]*" + particleListItem + "(?=[、，,。；;！？!?：:\\n]|$))", new String[][]{{null, "，", "带语气助词的并列项应用逗号，不用顿号"}});

            // 冲突标点串优先于“重复标点”处理，保证“，，。”这类输入能在一轮内归一。
            addRule("([，、]+)()([。；：])", new String[][]{{"", null, "标点多余"}, {null, "", "标点多余"}});
            addRule("([。；：])()([，、]+)", new String[][]{{"", null, "标点多余"}, {null, "", "标点多余"}});
            // 明显重复标点：问号/叹号的修辞性叠用不在此列。
            addRule("(，)()(，+)", new String[][]{{null, "", "逗号重复"}});
            // 中文聊天中“。。。/。。。。…”常用于表达无语、停顿等语气，保留三连及以上；
            // 只把更像误输入的“。。”（恰好两个）收敛成一个句号。
            addRule("(?<!。)(。)()(。)(?!。)", new String[][]{{null, "", "句号重复"}});
            addRule("(；)()(；+)", new String[][]{{null, "", "分号重复"}});
            addRule("(：)()(：+)", new String[][]{{null, "", "冒号重复"}});
            addRule("(、)()(、+)", new String[][]{{null, "", "顿号重复"}});

            // 同一外层句中连续用冒号引出转述时，把前一个冒号降为逗号。
            // 引号出现时不触发，因此“老师说：‘小王补充：……’”这类合法嵌套不会被改。
            String reportingVerb = "(?:说|表示|指出|强调|认为|解释|补充|回答|问道|写道|称|宣布|提醒|说明)";
            addRule("([^。！？\\n：]{1,30}" + reportingVerb + ")([ 　]*)(：)(?=[^。！？\\n“”‘’]{1,40}" + reportingVerb + "[ 　]*：)", new String[][]{{null, "，", "一个句子中通常只使用一个冒号"}});

            // E3-EMA 模型已独立通过大部分旧规则专项压力测试。以下仅保留在扩大上下文
            // 回归中仍有失败的窄规则：间歇状态修饰动作、部分方式状语、质地性质结构、
            // 以及固定专名/术语修饰名词；其余旧规则交给模型判断。
            String intermittentAdverbs = "断断续续|时断时续|一阵一阵|一声一声|接连不断|连续不断|时有时无|忽高忽低|忽远忽近";
            addProfessionalRule("(" + intermittentAdverbs + ")([ 　]*)([的得])(?=[ 　]*响(?=[着了过得个起下不又还并且而但却才就仍，,。；;！？!?：:、…\\n]|$))", new String[][]{{null, "地", "状态副词修饰动作“响”，应用“地”"}});

            String mannerModifiers = "耐心|认真|仔细|专心|用心|细心|热心|诚心|虚心|诚恳|礼貌|友好|冷静|平静|从容|谨慎|小心|努力|积极|主动|自觉";
            String mannerActions = "等待|倾听|听取|解释|说明|回答|答复|劝说|安慰|指导|教导|检查|核对|阅读|观察|处理|解决|分析|研究|学习|工作|准备|完成|记录|整理|操作|练习|思考|考虑|交流|沟通";
            addProfessionalRule("(" + mannerModifiers + ")([ 　]*)(得)(?=[ 　]*(?:" + mannerActions + "))", new String[][]{{null, "地", "方式词修饰动作，应用“地”"}});
            addProfessionalRule("(请[ 　]*(?:" + mannerModifiers + "))([ 　]*)([的得])(?=[ 　]*(?:" + mannerActions + "))", new String[][]{{null, ""}});
            addProfessionalRule("((?:他|她|它)[ 　]*准确)([ 　]*)([的得])(?=[ 　]*回答(?=[了着过，,。；;！？!?：:\\n]|$))", new String[][]{{null, "地", "“准确”修饰回答动作，应用“地”"}});

            String emotionActionModifiers = "高兴|开心|兴奋|激动";
            String emotionDynamicActions = "(?:跳(?:了|起|上|下)|笑(?:了|起|出|着)|喊(?:了|起|出)|说(?:道|着|了)|跑(?:了|起|出)|拍(?:起|着)|挥(?:了|起|着))";
            String emotionContinuation = "(?:不停|一直|连连|频频|不断|反复)";
            String emotionContinuationActions = "(?:跳|笑|喊|说|跑|拍|挥)";
            addProfessionalRule("(" + emotionActionModifiers + ")([ 　]*)(的)(?=[ 　]*" + emotionDynamicActions + ")", new String[][]{{null, "地", ""}});
            addProfessionalRule("(" + emotionActionModifiers + ")([ 　]*)(的)(?=[ 　]*" + emotionContinuation + "[ 　]*" + emotionContinuationActions + ")", new String[][]{{null, "地", "情绪状态作状语并接持续动作，应用‘地’"}});

            // 保护规则只屏蔽模型对命中字的推理，不直接产生纠错记录。
            String resultVerbs = "(?:插|扎|勒|压|挤|卡|塞|夹|顶|硌|磨|裹|捆|缠|撑)";
            String resultSubjects = "(?:袜子|袜口|鞋袜|鞋面|衣服|衣料|布料|皮肤|脚底|脚背|脚腕|手腕|伤口|肌肉|绳子|带子|木头|木板|石头|管口|幼苗|瓶口|电线|棚膜|货物|地砖|他|她|它|人)";
            String resultSignals = "(?:直|都|也|已经|快|几乎|差点|深深|完全|紧紧|明显|生疼|发麻|发疼|发红|破了|陷入|陷进|陷得|起了|变得|喘不过气|动不了|鼓了|弯不过来|晃不动)";
            String textureQualities = "(?:柔软|细腻|坚硬|粗糙|轻薄|柔韧|顺滑|松散|绵密|光滑|冰凉|厚实|温润|干涩|黏腻|蓬松|紧实|均匀|致密|疏松|弹性|韧性|硬度|软硬|粗细)";
            String fixedModifiers = "(?:营地|质地|地拉那|地中海|地衣|地黄|地缘|地质|地震|彼得|圣彼得堡|的黎波里|的里雅斯特|的的喀喀湖|巴尔的摩|蒙得维的亚|塞得港|得荣县)";
            String fixedNounHeads = "(?:研究员|研究中心|资料|样本|气候|街道|港口|灯光|补给|照明|结构|触感|差异|特征|条目|叶片|覆盖率|编号|记录|论文|天气|货轮|冬夜|航线|数据|报告|土壤|价格|来源|用途)";
            String degreeStateHeads = "(?:土|泥土|土壤|地面|路面|石头|木板|绳子|鞋子|衣服|天气|太阳|屋里|房间|声音|灯光)";
            String degreeAdjectives = "(?:硬|软|冷|热|干|湿|累|困|疼|痛|酸|麻|紧|松)";
            String degreeClauseSubjects = "(?:铁锹|手|脚|人|孩子|他|她|我|你|衣服|鞋|袜子|门|窗|绳子)";
            String degreeClauseSignals = "(?:很难|无法|不能|动不了|插不|拿不|抬不|走不|受不了|睁不开|喘不过|发麻|发疼|通红|弯不过|晃不动)";
            String reduplicatedSimileStates = "(?:红红|蓝蓝|白白|黑黑|黄黄|绿绿|粉粉|亮亮|圆圆|软软|暖暖|冷冷|甜甜|香香|嫩嫩|胖胖|瘦瘦|高高|矮矮)";
            String imaginedDegree = "(?:那么|这么|如此|那样|这样)[ 　]*(?:严重|简单|容易|困难|复杂|糟糕|美好|漂亮|好|坏|难|快|慢|大|小|高|低|冷|热|远|近|深|浅|强|弱)";
            String serialMannerUnits = "(?:一件件|一张张|一页页|一步步|一点点|一遍遍|一次次|一个个|一行行|一句句|一声声|一项项|一条条|一层层|一字一句)";
            String serialMannerActions = "(?:讲|说|读|写|看|拿|放|摆|收|整理|检查|核对|解释|说明|递|搬|捡|装|塞|贴|记|数|翻|抄|念|展示|给)";
            String emotionDegreeSignals = "(?:差点|差一点|几乎|险些|都快|快要)";
            String emotionDegreeActions = "(?:跳|站|蹦|哭|笑|喊|跑|摔|跌|晕|叫)";
            addProtectedTargetPattern("[“‘\\\"]([的地得做作])(?=[”’\\\"])");
            // 这些旧白名单词只在引号内作为字面词条时仍有误判；用精确上下文保护，
            // 避免“心得”误伤“耐心得等待/小心得搬运”等真实错误。
            addProtectedTargetPattern("[“‘\\\"](?:厕所|懂|留|腰)(的)(?=[”’\\\"])");
            addProtectedTargetPattern("[“‘\\\"]心(得)(?=[”’\\\"])");
            addProtectedTargetPattern("[“‘\\\"](地)(?=处[”’\\\"])");
            // “开心得笑起来”等既可表示程度结果，也可能被模型当成状语；保留用户原字。
            addProtectedTargetPattern("(?:" + emotionActionModifiers + ")(得)(?=[ 　]*" + emotionDynamicActions + ")");
            addProtectedTargetPattern("(?:" + emotionActionModifiers + ")(地)(?=[ 　]*" + emotionContinuation + "[ 　]*" + emotionContinuationActions + ")");
            addProtectedTargetPattern("(?:并没有|没有|远没有)[ 　]*想象(的)(?=[ 　]*" + imaginedDegree + ")");
            addProtectedTargetPattern(degreeStateHeads + "(?:很|太|真|特别|非常)?" + degreeAdjectives + "(得)(?=[ 　]*" + degreeClauseSubjects + "(?:都|也)?" + degreeClauseSignals + ")");
            addProtectedTargetPattern(resultVerbs + "(得)(?=[ 　]*" + resultSubjects + "[^，,。；;！？!?：:\\n]{0,12}" + resultSignals + ")");
            addProtectedTargetPattern("质地(的)(?=[ 　]*" + textureQualities + ")");
            addProtectedTargetPattern(fixedModifiers + "(的)(?=[ 　]*" + fixedNounHeads + ")");
            // 明确的合法状语/定语边界；只保护原字，不把相反写法强制纠正。
            addProtectedTargetPattern("快速(地)(?=[ 　]*增长)");
            addProtectedTargetPattern("反复(地)(?=[ 　]*讨论)");
            addProtectedTargetPattern("[“‘\\\"]规律(地)(?=[ 　]*变化[”’\\\"])");
            addProtectedTargetPattern("规律(的)(?=[ 　]*(?:变化|运动|动作|摆动|晃动|抽动|撸动|节奏|波动|起伏|震动|振动|脉动|活动))");
            // 小说口语常见“红红的像…… / 蓝蓝的像……”；HCAM会高置信偏向“得”，保留原“的”。
            addProtectedTargetPattern(reduplicatedSimileStates + "(的)(?=[ 　]*(?:像|如同|仿佛))");
            // 500段小说复测：重复量词作方式状语是稳定低置信区，正确“地”直接保护。
            addProtectedTargetPattern(serialMannerUnits + "(地)(?=[ 　]*" + serialMannerActions + ")");
            // “高兴得差点跳起来”明确表达程度/结果时保护“得”；不把“高兴地差点……”一刀切改掉。
            addProtectedTargetPattern("(?:" + emotionActionModifiers + ")(得)(?=[ 　]*" + emotionDegreeSignals + "[^，,。；;！？!?：:\n]{0,14}" + emotionDegreeActions + ")");
            // HCAM 7,152 位回归 + 用户小说句新增：只保护明确的名词化/定语结构，避免把“响”作动词等情形一刀切。
            addProtectedTargetPattern("发出[^，,。；;！？!?：:\\n]{0,10}(的)(?=响(?:[，,。；;！？!?：:\\n]|$))");
            addProtectedTargetPattern("(?:看|见|听|说|写|画|拍|买|拿|做|选|找|等|想|要|用|吃|喝|穿|戴)(的)(?=[ 　]*(?:一直|都是|就是|不过|也|还|仍))");
            addProtectedTargetPattern("当地(的)(?=[ 　]*[\\u4E00-\\u9FFF])");
            addProtectedTargetPattern("当地(地)(?=[ 　]*(?:下|方|图|形|温|力|道|铁|质))");
            addProtectedTargetPattern("熟悉(地)(?=[ 　]*形)");
            addProtectedTargetPattern("地处[^，,。；;！？!?：:\\n]{1,8}(的)(?=[ 　]*(?:营地|村庄))");
            addProtectedTargetPattern("得主(的)(?=[ 　]*得票)");
            addProtectedTargetPattern("得当(的)(?=[ 　]*[\\u4E00-\\u9FFF])");
            // “设备挤的衣服都已打包”属于定语结构，新模型仍可能误改为“得”。
            addProtectedTargetPattern(resultVerbs + "(的)(?=[ 　]*" + resultSubjects + "[ 　]*(?:都|也)?[ 　]*(?:已经|已|早已)?[ 　]*(?:送走|入库|编号|消毒|打包|洗净|复检|拆下|收好|拍照|归档|更换))");

            // HCAM 小说长尾保护：只保护语法边界明确的正确“的/地”，不扩大通用白名单。
            // 重点覆盖实测出现的“不受控制地”、名词化“断断续续的挣扎”等高置信误判；
            // 同时用动作/名词边界限制，避免把“断断续续的哭声”“回答方式”等合法结构混在一起。
            addProtectedTargetPattern("不受控制(地)(?=[ 　]*(?:颤抖|抽搐|摇晃|后退|流泪|发笑|尖叫|倒下|扑(?:向|到|过去)|弯下|抖动|移动|行走|前进)(?!现象|动作|症状|反应|声音))");
            addProtectedTargetPattern("断断续续(地)(?=[ 　]*(?:说(?:完|着|了|道|起)|讲(?:述|完|起)|回答|解释|喘(?:着|息|气)|咳嗽|哭(?:了|起来|着|出声)|抽泣|呼吸|传来|响(?:起|着|了)|闪烁|移动|行走|前进|后退|颤抖|抖动|挣扎(?:着|起来|了)))");
            addProtectedTargetPattern("断断续续(的)(?=[ 　]*(?:声音|哭声|呼吸声|信号|掌声|回忆|震动|振动))");
            addProtectedTargetPattern("(?:感受(?:到)?|感觉(?:到)?|察觉(?:到)?|听(?:见|到)?|注意(?:到)?|发现)[^，,。；;！？!?：:\\n]{0,8}断断续续(的)(?=[ 　]*挣扎(?=[ 　]*(?:[，,。；;！？!?：:\\n]|$|越来越|已经|仍然|逐渐|开始|停止|持续|变得|让|使|令)))");
            addProtectedTargetPattern("和颜悦色(地)(?=[ 　]*(?:解释|询问|安慰|接待|回答|劝说|提醒|说道|说|问|交谈|沟通)(?!方式|方法|内容|结果|过程|语气|态度))");
            addProtectedTargetPattern("反复(的)(?=[ 　]*(?:强调|提醒)(?:让|使|令))");
            addProtectedTargetPattern("(?:这是|那是)(?:小心翼翼|战战兢兢)(的)(?=[ 　]*(?:试探|回答)(?:[，,。；;！？!?：:\\n]|$))");

            addProfessionalRule("(" + fixedModifiers + ")([ 　]*)([地得])(?=[ 　]*" + fixedNounHeads + ")", new String[][]{{null, "的", "专名或固定术语修饰名词，应用“的”"}});
            addProfessionalRule("(质地)([ 　]*)([地得])(?=[ 　]*" + textureQualities + ")", new String[][]{{null, "的", "“质地”后的性质名词化结构应用“的”"}});
            addProfessionalRule("(" + degreeStateHeads + "(?:很|太|真|特别|非常)?" + degreeAdjectives + ")([ 　]*)([的地])(?=[ 　]*" + degreeClauseSubjects + "(?:都|也)?" + degreeClauseSignals + ")", new String[][]{{null, "得", "程度或结果补语应用“得”"}});
            addProfessionalRule("(拍立)([ 　]*)([的地])(?=[ 　]*(?:相纸|照片|相机|胶片|成像|产品|设备|机身|耗材|纸))", new String[][]{{null, "得", "固定词“拍立得”"}});
            addProfessionalRule("(" + reduplicatedSimileStates + ")([ 　]*)([地得])(?=[ 　]*(?:像|如同|仿佛))", new String[][]{{null, "的", "叠词状态后接比喻，保留口语定式“……的像/如同……”"}});
            addProfessionalRule("(" + serialMannerUnits + ")([ 　]*)([的得])(?=[ 　]*" + serialMannerActions + ")", new String[][]{{null, "地", "重复量词短语作方式状语，应用“地”"}});
            // “高兴的差点跳起来”明确错误，纠为“得”；“高兴地差点……”可能有合法状语读法，不强制改。
            addProfessionalRule("(" + emotionActionModifiers + ")([ 　]*)(的)(?=[ 　]*" + emotionDegreeSignals + "[^，,。；;！？!?：:\n]{0,14}" + emotionDegreeActions + ")", new String[][]{{null, "得", "程度/结果补语应用“得”"}});
            addProfessionalRule("((?:并没有|没有|远没有)[ 　]*想象)([ 　]*)([地得])(?=[ 　]*" + imaginedDegree + ")", new String[][]{{null, "的", "‘没有想象的那么/这么……’是名词化比较结构，应用‘的’"}});

            String locations = "家|家里|家中|家外|卧室|卧房|厨房|客厅|卫生间|洗手间|厕所|茅房|阳台|书房|餐厅|饭厅|浴室|走廊|走道|院子|庭院|地|车|超市|商场|商店|菜市场|农贸市场|便利店|小卖部|饭店|酒店|旅馆|宾馆|招待所|餐馆|食堂|咖啡厅|咖啡馆|酒吧|网吧|电影院|戏院|剧院|银行|邮局|理发店|药店|诊所|门|商铺|店|医院|学校|幼儿园|小学|中学|初中|高中|大学|教室|图书馆|操场|宿舍|办公楼|公司|办公室|工厂|厂里|车间|会议室|派出所|警察局|公安局|消防队|法院|政府|监狱|看守所|基地|营地|阵地|车站|火车站|高铁站|地铁站|公交站|客运站|飞机场|机场|码头|港口|停车场|加油站|收费站|高速上|马路上|街上|路上|十字路口|桥上|桥下|隧道里|铁轨上|公园|动物园|植物园|游乐场|游乐园|广场|体育馆|体育场|游泳池|健身房|博物馆|展览馆|美术馆|海|沙滩|海岸|山上|山下|山顶|树林|森林|湖边|河边|江边|水里|田里|农田|地里|村|乡|农村|城里|城市|市区|郊区|景区|野外|这里|那里|哪里|这儿|那儿|哪儿|上面|下面|里面|外面|上边|下边|里边|外边|左边|右边|前面|后面|旁边|附近|远处|高处|低处|深处|内部|外部|中心|中间|顶上|底下|背后|面前";
            addRule("((?:我|你|您|他|她|它|我们|你们|他们|她们|大家|自己|谁|还|正|已经|仍然))([ 　]*)(再)(?=[ 　]*(?:" + locations + ")(?:里|内|中|外)?(?:[，,。；;！？!?：:\n]|$|办公|工作|休息|睡觉|学习|等待|吃饭|住宿|开会))", new String[][]{{null, "在"}});
            addRule("(在)( *)(次|度)(?=$|[，,。；;！？!?：:\\n]|出现|发生|出发|进入|返回|离开|重逢|见面|来到|出席|参加|强调|说明|提醒|提出|拒绝|尝试|确认|检查|上涨|下降|提高|降低|获得|失去|当选|获奖|夺冠|冲高|回落)", new String[][]{{"再", null}});
            addRule("(在)( *)(三)(?=考虑|叮嘱|强调|犹豫|确认|要求|请求|推辞|声明|警告|追问|申明)", new String[][]{{"再", null}});
            addRule("(截止)( *)(目前|现在)", new String[][]{{"截至", null}});




            // 2026-10 全量基准回归（20套/68,607句）：数字转汉字规则误改460处、仅1处正确，已删除。
            // "4名官员/5次下潜/7楼/8点"等阿拉伯数字用法在新闻与统计文体中完全规范，不再强制转换。
            String[] weekdays = {"", "一", "二", "三", "四", "五", "六", "日"};
            for (int i = 1; i <= 7; i++) addRule("(?<![0-9零〇一二两三四五六七八九十百千万亿第])(星期|周|礼拜)( *)(" + i + ")(?=$|[\\s，,。；;！？!?：:、”’）)]|上午|下午|晚上|早上|凌晨|中午|早晨|晚间|见面|开会|放假|休息|上班)", new String[][]{{null, weekdays[i]}});
            String[] lunarDays = {"", "初一", "初二", "初三", "初四", "初五", "初六", "初七", "初八", "初九", "初十", "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八", "十九", "二十", "二十一", "二十二", "二十三", "二十四", "二十五", "二十六", "二十七", "二十八", "二十九", "三十"};
            for (int i = 1; i <= 30; i++) addRule("(正月|腊月|冬月)( *)(" + i + ")(?=日|号|$|[\\s，,。；;！？!?：:、”’）)]|上午|下午|晚上|早上|凌晨|中午|早晨|晚间|见面|开会|放假|休息|上班)", new String[][]{{null, lunarDays[i]}});
            String[] simple = {"", "一", "二", "三", "四", "五", "六", "七", "八", "九", "十"};
            for (int i = 1; i <= 10; i++) addRule("(?<![起当最年月])(初)( *)(" + i + ")(?=日|号|$|[\\s，,。；;！？!?：:、”’）)]|上午|下午|晚上|早上|凌晨|中午|早晨|晚间|见面|开会|放假|休息|上班)", new String[][]{{null, simple[i]}});
            // 同上回归："8点/7楼/3班"单独数字转换全部为合法用法（0正确/约30误改），连同"达→有"两规则一并删除。

            addRule("(?:(?<=数万|几万|上万)|(?<=数十万|数百万))(名)([^，,。；;！？!?：:、\\n]{0,8}?)(人群)", new String[][]{{"人的", ""}});
            addRule("(减少|降低|缩短|下降|减小|缩小)([^，,。；;！？!?：:、\\n]{0,15}?[0-9十百千万亿两半])(倍)", new String[][]{{null, "倍", "下降/减小等不能用倍数表示"}});
            addRule("(随便|随意)( *)(苟同)", new String[][]{{"", null}});
            addRule("(非常|十分|极其|特别|尤其)( *)(酷爱|惨重|硕大|嗜好|痛恨|严禁)", new String[][]{{"", null}});
            addRule("(发自内心的?|从内心里的?|打心眼里的?)( *)(由衷)", new String[][]{{"", null}});
            // 2026-10 回归修复：“人民币二亿元”等金融法律计数惯例不改。
            // “二万元”等金融计数属于合法表达，保留原文。
            // “再这里/再那里”后接活动动词时可确定为介词；不处理“再后面”等合法方位表达。
            addRule("(再)()(这里|那里|这儿|那儿|此处|此地|这边|那边|车上)(?=浪费|继续|工作|学习|休息|等待|停留|逗留|碍|吃|喝|睡|办公)", new String[][]{{"在", null}});
            // 只在明确的引语结构中修正“说到”，保留“说到这个话题”等表达。
            addRule("(?<=[他她时]|笑着|接着|转发)(说到)([ 　]*)([:：])(?=[“”‘])", new String[][]{{"说道", null}});
            // “10月1日前往”并不必然表示截止日期，不能自动插入“之前”。
            addRule("(几个)([^的，。；！？、\\n]{0,8}?)(校长|老师|领导|教授|医生|警察|党员|干部)", new String[][]{{"几位", null}});
            addRule("(出于)([^，,。；;！？!?：:、\\n]{1,15}?)(的决定)", new String[][]{{"", "决定"}});
            addRule("(具有)([ 　]*(?:消食|化积|润肠|通便|清热|解毒|活血|化瘀|消肿|止痛|健脾|养胃|安神|补血|益气|滋阴|补肾|祛风|除湿|润肺|化痰|止咳|平喘|抗氧化|抗菌|抑菌|消炎)(?:[、和及与 　]*(?:消食|化积|润肠|通便|清热|解毒|活血|化瘀|消肿|止痛|健脾|养胃|安神|补血|益气|滋阴|补肾|祛风|除湿|润肺|化痰|止咳|平喘|抗氧化|抗菌|抑菌|消炎))*[ 　]*)()(?=[，,。；;！？!?：:\\n]|$)", new String[][]{{null, "的功效", "成分残缺，补充宾语"}});

            // 口语省略宾语：如“打自由的，……”的“的”指代某种玩法，不是状语“地”。
            // 只覆盖选玩法/选物品后的句末或停顿，避免保护“自由的探索”等需纠错的用法。
            addProtectedTargetPattern("(?:打|玩|开|刷|排|试|选|挑|要|喜欢)[ 　]*(?:自由|休闲|经典|普通|简单|困难)(的)(?=[ 　]*(?:[，,。！？!?；;：:\\n”’\"]|$))");
            addProtectedTargetPattern("(?:选|挑|买|拿|点|要|穿|吃|喝)[ 　]*(?:便宜|贵|好看|漂亮|红色|蓝色|绿色|白色|黑色|好吃)(的)(?=[ 　]*(?:[，,。！？!?；;：:\\n”’\"]|$))");
            addProtectedTargetPattern("(?:打|玩|开|刷|排|试|选|挑)[ 　]*(?:自由|休闲|经典|普通|简单|困难)(的)(?=[ 　]*(?:来(?:练级|打怪|刷图|探索|体验|做任务)|就(?:好|行|可以)|也(?:好|行)))");
            // 明确的定语名词搭配，不扩大到“自由的选择/行动/探索”等动词歧义。
            addProtectedTargetPattern("自由(的)(?=[ 　]*(?:模式|副本|关卡|地图|玩法|世界|灵魂|思想|权利|意志|空间|天空))");

            // 纠错 Pro 扩大五字回归：只保护实测合法的原字，限定后续词义/句式边界。
            addProtectedTargetPattern("(?:工作|任务|活儿|作业)(得)(?=分(?:[两三四五六几]|[2-9])天(?:做|完成|处理))");
            addProtectedTargetPattern("(?:别(?:再)?(?:提|说|争|吵|跟[^，,。；;！？!?：:\\n]{1,6}一般见识)[^，,。；;！？!?：:\\n]{0,16}|就当[^，,。；;！？!?：:\\n]{1,20})(得)(?=了(?:呗|吧|嘛)?(?:[，,。；;！？!?：:\\n”’\"]|$))");
            addProtectedTargetPattern("(?:太|真|这么|那么|很)能(作)(?=了?(?:[，,。；;！？!?：:\\n”’\"]|$))");
            addProtectedTargetPattern("(?:又|还|别)(作)(?=(?:什么[？?，,。！!]|了(?:[，,。；;！？!?：:\\n”’\"]|$)))");
            addProtectedTargetPattern("(?:说|写|讲|做)(的)(?=对(?:我|你|他|她|我们|你们|他们|她们)(?:很|非常|十分|特别)?(?:重要|有用|有意义|有帮助))");
            addProtectedTargetPattern("(?:说|做|写|画)(的)(?=哪(?:儿|里)(?:不好|不对|有问题))");
            addProtectedTargetPattern("(做)(?=的(?:画框|模型|手工|饭|菜|汤|饼干|面包|蛋糕|风筝))");
            addProtectedTargetPattern("(地)(?=温(?:[，,。；;！？!?：:\\n”’\"]|$|度|变化|测量|记录|数据))");
            addProtectedTargetPattern("互相(地)(?=(?:碰撞|挤压|拉扯|推搡)(?!声|声音|过程|动作))");
            addProtectedTargetPattern("(?:地图[^，,。；;！？!?：:\\n]{0,12}|位置|地界|路线)标(得)(?=(?:很|非常|十分|特别)?清楚)");
            addProtectedTargetPattern("(作)(?=(?:了|过|出)?(?:一些|许多|多次|不同的|额外的|必要的|适当的|细微的|进一步的)?(?:尝试|变化|改动|调整|安排|处理|说明|判断|决定))");
            addProtectedTargetPattern("(做)(?=(?:进一步的)?(?:分类统计|统计|分析|计算|记录|测量))");
            addProtectedTargetPattern("所(作)(?=的作品)");
            addProtectedTargetPattern("(?:自己|我|你|他|她|谁|大家)(作)(?=主(?:[，,。；;！？!?：:\\n”’\"]|$))");
            addProtectedTargetPattern("[“‘\"](做)(?=客[”’\"])");
            addProtectedTargetPattern("(?:高兴|兴奋|激动|开心)(得)(?=(?:拍(?:手|了一下桌子)|直(?:拍手|点头)|笑(?:起来|了)))");
            addProtectedTargetPattern("格外(地)(?=小心(?:[，,。；;！？!?：:\\n]|$))");
            addProtectedTargetPattern("(?:做|写|画|选)(的)(?=(?:很|十分|非常)?好[，,](?:是|就是|正是|都是)[^，,。；;！？!?：:\\n]{0,12}(?:那一件|那一个|一件|一个|那一本))");
            addProtectedTargetPattern("(?:说|写|讲)(的)(?=(?:很|非常|十分|相当|特别)?(?:清楚|完整|具体|全面)[，,](?:已经)?没有什么(?:需要|可)(?:补充|修改|解释))");

            // ===== 2026-10 全量基准（20套/68,607句）误改回归：新增保护正则 =====
            // 以下均来自实测高置信误改：只保护原字正确的情况，不拦截任何真实纠错方向。
            // "马公的GE222航班"类：的+字母/数字必为定语。
            addProtectedTargetPattern("(的)(?=[ 　]*[0-9A-Za-z])");
            // "所在的荥阳市/所在的省级政府"：所在的为定语结构。
            addProtectedTargetPattern("所在(的)");
            // "事发地/安葬地/犯罪地/居所地/到达地/出生地"等法律新闻高频地名复合词，地是名词语素。
            addProtectedTargetPattern("(?:事发|安葬|犯罪|居所|出生|到达|施工|作案|聚会|比赛|考试|面试|办公|审判|服役|居住|集合|降落|停靠|事故|发案|征地|拆迁|旅游|度假|商业|工业|农业|法院)(地)");
            // 常见"X地"名词：各地/基地/营地/工地/用地/产地/场地/园地/耕地/墓地等。
            addProtectedTargetPattern("(?:各|腹|属|领|圣|墓|基|营|驻|阵|工|用|宅|产|场|园|草|林|耕|湿|沙|盆|谷)(地)(?=[ 　]*[\\u4E00-\\u9FFF])");
            // "接地气/连接地气"：地气是名词。
            addProtectedTargetPattern("(地)(?=气)");
            // "土地的使用权"类：的+权类名词必为定语。
            addProtectedTargetPattern("(的)(?=[ 　]*权)");
            // "大学的球场/最高的监测站"类：的+机构场所名词必为定语。
            addProtectedTargetPattern("(的)(?=[ 　]*(?:球场|机场|广场|操场|工厂|医院|公司|中心|公园|车站|酒店|学校|大学|学院|政府|部门|机构|组织|团体|地图|图表|图形|图案|管线|线路|电路|管网|系统|平台|项目|工程|产品|作品|梦想|航班|航线|车队|球队|乐队|军队|法院|检察院|派出所|监测站|研究所|研究院|委员会|管理局|指挥部|办事处|服务站))");
            // "投资的时机"类：的+时必为定语。
            addProtectedTargetPattern("(的)(?=[ 　]*时)");
            // "不是实的，而是空的"类：的字名词化后接"而是"。
            addProtectedTargetPattern("(的)(?=[ 　]*[，,]而是)");
            // 程度/结果补语被反向误改："堵得慌/痛得厉害/恢复得快/医得好"，模型不得把正确的得改成的。
            addProtectedTargetPattern("(得)(?=[ 　]*(?:慌|厉害|要命|要死|不行|受不了|喘不过|说不出|站不稳|走不动|直流泪|直打滚|直跺脚|直哆嗦|直冒汗|直咬牙))");
            addProtectedTargetPattern("(得)(?=[ 　]*(?:好|快|慢|多|少))");
            // "得了甲减/得病率/怎么得的/了得"：得字本身正确。
            addProtectedTargetPattern("(得)(?=病)");
            addProtectedTargetPattern("(得)(?=了)");
            addProtectedTargetPattern("(得)(?=的)");
            addProtectedTargetPattern("了(得)");
            addProtectedTargetPattern("(?:气|急)(得)(?=[ 　]*话)");
            // "当作"是规范写法；"做法"是规范名词；"做甚"为口语疑问；"做众生马牛"为佛教引文。
            addProtectedTargetPattern("当(作)");
            addProtectedTargetPattern("(做)(?=法)");
            addProtectedTargetPattern("(做)(?=甚)");
            addProtectedTargetPattern("(做)(?=众生)");
            // "不作不死/这人不作"：网络与口语"作"(zuō)正确。
            addProtectedTargetPattern("不(作)(?=不死)");
            addProtectedTargetPattern("(?:人|他|她|你|我)(作)(?=[，,。！？!?；;\\n]|$)");
            // "扫地/拖地/擦地/落地"等动宾结构，地为宾语名词。
            addProtectedTargetPattern("(?:扫|拖|擦|洗|种|耕|犁|翻|铺|垫|落|坠|着|触|撑)(地)");
            // "再三地要求"：再三地作状语正确。
            addProtectedTargetPattern("再三(地)");
            // 句中状语"幸运地，/辛苦地，"：地字正确。
            addProtectedTargetPattern("(?:幸运|辛苦|奇怪|突然|果然|居然|显然|自然|意外|遗憾|失望|无奈|悲哀|可怜|可悲|可笑|可怕|可惜|难得|恰好|凑巧|无意)(地)(?=[ 　]*[，,])");
            // 拟声"噗"地一声：与"的一声"同为合法。
            addProtectedTargetPattern("(地)(?=一声)");
            // "梦幻般地起伏"：般+地+动词为状语结构。
            addProtectedTargetPattern("(?:般)(地)(?=[ 　]*(?:起伏|交错|流动|涌动|浮现|蔓延|展开|延伸|旋转|飞舞|飘荡|摇摆|闪烁|跳动|变化))");
            quantRules.put('牛', new QuantifierRule("头", "头")); quantRules.put('马', new QuantifierRule("匹", "匹")); quantRules.put('狗', new QuantifierRule("只", "只条")); quantRules.put('猫', new QuantifierRule("只", "只")); quantRules.put('猪', new QuantifierRule("头", "头口只")); quantRules.put('羊', new QuantifierRule("只", "只头")); quantRules.put('鸡', new QuantifierRule("只", "只")); quantRules.put('鸭', new QuantifierRule("只", "只")); quantRules.put('鹅', new QuantifierRule("只", "只")); quantRules.put('鸟', new QuantifierRule("只", "只")); quantRules.put('鱼', new QuantifierRule("条", "条尾")); quantRules.put('门', new QuantifierRule("扇", "扇部")); quantRules.put('车', new QuantifierRule("辆", "辆部台座个"));
        } catch (Throwable error) { rulesAttempted=false;gramRules.clear();quantRules.clear();protectedTargetPatterns.clear();throw new IllegalStateException("语法规则加载失败",error); }
    }

    public static final String NUMS = "一二两三四五六七八九十百千万这那几某";
    public static final String KNOWN_QUANTS = "个只条头匹辆部台口尾座把本名位";
    // 保留仍会误改的词汇；仅在两种量化均通过独立上下文回归后移除保护。
    public static final String[] IGNORE_WORDS = {"得意", "工作", "怎的", "觉得", "拍立得", "打的", "别地", "佛得角", "安的列斯", "的卢", "地王", "地素时尚", "地基", "地高辛", "地氯雷他定", "地诺孕素", "地尔硫卓", "地奥司明", "地芬尼多", "地拉罗司", "得空", "得耳布尔", "大地", "地窝堡", "地峡", "地热", "得梅因", "得力", "得势", "得名", "得志", "得陇望蜀", "地屈孕酮", "地特胰岛素", "得手", "海得拉巴", "地蚕", "地表", "地籍", "地标", "取得", "难得", "地黄", "地耳", "地被菊", "地磁"};
    public static final String[] WHITE_LIST = {};

    public static boolean isSafeCharAfterNoun(char c) {
        if (c == '\0' || c < '\u4E00' || c > '\u9FFF') return true;
        return "的了着过是在被把让给对和与同或就也都还很太真会能可要想走跑跳吃喝咬叫哭笑我看你他她它们这那\n".indexOf(c) >= 0;
    }

    public static final class TypoMatch {
        public final String source, correction;
        public final boolean custom;
        TypoMatch(String source, String correction, boolean custom) { this.source = source; this.correction = correction; this.custom = custom; }
    }

    // Immutable packed trie: publish once, retain one snapshot throughout a correction job.
    public static final class TypoIndex {
        final int[] roots, first, edges, terminal;
        final char[] labels;
        final String[] sources, corrections;
        final boolean[] customs;
        final Map<String, String[]> exclusions;
        final int maxLength;
        final String[] protectedWords;
        private TypoIndex(int[] roots, int[] first, int[] edges, int[] terminal, char[] labels,
                          String[] sources, String[] corrections, boolean[] customs, Map<String, String[]> exclusions, int maxLength) {
            this.roots = roots; this.first = first; this.edges = edges; this.terminal = terminal; this.labels = labels;
            this.sources = sources; this.corrections = corrections; this.customs = customs; this.exclusions = exclusions; this.maxLength = maxLength;
            List<String> protectedList = new ArrayList<>();
            for (int i = 0; i < sources.length; i++) if (customs[i]) protectedList.add(sources[i]);
            protectedWords = protectedList.toArray(new String[0]);
        }
        static TypoIndex build(Map<String, String> words, Set<String> custom, Map<String, String[]> exceptions) {
            String[] sources = words.keySet().toArray(new String[0]); Arrays.sort(sources);
            int capacity = 1, maxLength = 0;
            for (String word : sources) { capacity += word.length(); maxLength = Math.max(maxLength, word.length()); }
            int[] parents = new int[capacity], counts = new int[capacity], terminals = new int[capacity], path = new int[maxLength + 1];
            char[] chars = new char[capacity]; String previous = ""; int size = 1;
            String[] corrections = new String[sources.length]; boolean[] customs = new boolean[sources.length];
            for (int entry = 0; entry < sources.length; entry++) {
                String word = sources[entry]; int common = 0;
                while (common < previous.length() && common < word.length() && previous.charAt(common) == word.charAt(common)) common++;
                for (int i = common; i < word.length(); i++) {
                    int node = size++, parent = path[i]; parents[node] = parent; counts[parent]++; chars[node] = word.charAt(i); path[i + 1] = node;
                }
                terminals[path[word.length()]] = entry + 1;
                corrections[entry] = words.get(word); customs[entry] = custom.contains(word); previous = word;
            }
            int[] first = new int[size + 1], edges = new int[size - 1], roots = new int[65536];
            for (int i = 0; i < size; i++) first[i + 1] = first[i] + counts[i];
            int[] next = first.clone();
            for (int node = 1; node < size; node++) { edges[next[parents[node]]++] = node; if (parents[node] == 0) roots[chars[node]] = node; }
            return new TypoIndex(roots, first, edges, Arrays.copyOf(terminals, size), Arrays.copyOf(chars, size),
                    sources, corrections, customs, Collections.unmodifiableMap(new HashMap<>(exceptions)), maxLength);
        }
        int child(int node, char c) {
            if (node == 0) return roots[c];
            int lo = first[node], hi = first[node + 1] - 1;
            while (lo <= hi) { int mid = (lo + hi) >>> 1, child = edges[mid]; char key = labels[child];
                if (key < c) lo = mid + 1; else if (key > c) hi = mid - 1; else return child; }
            return 0;
        }
        boolean excluded(String text, int index, int entry) {
            String[] words = exclusions.get(sources[entry]);
            if (words == null) return false;
            int end = index + sources[entry].length();
            for (String word : words) {
                int found = text.indexOf(word, Math.max(0, end - word.length()));
                if (found >= 0 && found <= index && found + word.length() >= end) return true;
            }
            return false;
        }
        boolean[] protectedPositions(String text) {
            boolean[] positions = new boolean[text.length()];
            for (String word : protectedWords) for (int at = text.indexOf(word); at >= 0; at = text.indexOf(word, at + 1))
                Arrays.fill(positions, at, at + word.length(), true);
            return positions;
        }
        public TypoMatch find(String text, int index) { return find(text, index, null); }
        TypoMatch find(String text, int index, boolean[] protectedPositions) {
            if (index < 0 || index >= text.length()) return null;
            return findLongest(text, index, index, 0, protectedPositions);
        }
        private TypoMatch findLongest(String text, int start, int cursor, int node, boolean[] protectedPositions) {
            if (cursor < text.length()) {
                int next = child(node, text.charAt(cursor));
                if (next != 0) { TypoMatch longer = findLongest(text, start, cursor + 1, next, protectedPositions); if (longer != null) return longer; }
            }
            int entry = terminal[node] - 1;
            if (entry < 0 || (!customs[entry] && isFalsePositiveTypo(text, start, sources[entry]))) return null;
            if (!customs[entry] && Proofreader.touchesIdentifier(text, start, start + sources[entry].length())) return null;
            if (!customs[entry] && !sources[entry].equals(corrections[entry]) && protectedPositions != null)
                for (int i = start; i < start + sources[entry].length(); i++) if (protectedPositions[i]) return null;
            if (!customs[entry] && Proofreader.crossesRepetition(text, start, sources[entry], corrections[entry])) return null;
            if (excluded(text, start, entry)) return new TypoMatch(sources[entry], sources[entry], customs[entry]);
            if (!customs[entry] && !sources[entry].equals(corrections[entry]) && conflicts(text, start, sources[entry], corrections[entry])) return null;
            return new TypoMatch(sources[entry], corrections[entry], customs[entry]);
        }
        boolean conflicts(String sentence, int index, String source, String correction) {
            if (source.equals(correction) || sources.length == 0) return false;
            String simulated = sentence.substring(0, index) + correction + sentence.substring(index + source.length());
            int end = index + correction.length();
            for (int cursor = Math.max(0, index - maxLength + 1); cursor < end; cursor++) {
                int node = 0;
                for (int pos = cursor; pos < simulated.length(); pos++) {
                    node = child(node, simulated.charAt(pos)); if (node == 0) break;
                    int entry = terminal[node] - 1;
                    if (entry >= 0 && ((cursor < index && pos + 1 > index) || pos + 1 > end)
                            && !sources[entry].equals(corrections[entry]) && !excluded(simulated, cursor, entry)) return true;
                }
            }
            return false;
        }
    }
    public static TypoMatch findTypoMatch(String sentence, int index) { return typoIndex.find(sentence, index); }

    public static boolean isFalsePositiveTypo(String sentence, int index, String source) {
        for (String white : WHITE_LIST) {
            if (white == null || white.isEmpty()) continue;
            int searchStart = Math.max(0, index - white.length()), searchEnd = Math.min(sentence.length(), index + source.length() + white.length());
            int found = sentence.indexOf(white, searchStart);
            while (found >= 0 && found + white.length() <= searchEnd) {
                int start = found, end = start + white.length();
                if (start < index + source.length() && end > index) return true;
                found = sentence.indexOf(white, found + 1);
            }
        }
        
        if (source.charAt(0) == '做' || source.charAt(0) == '作') {
            if (index > 0 && "创去要在该想会能可来把给多没不曾刚才将正就爱肯敢配帮替让叫使令".indexOf(sentence.charAt(index - 1)) >= 0) return true;
            if (index + source.length() < sentence.length() && "扇筝联山发牙眼肢手脚衣裤帽鞋饭菜汤了".indexOf(sentence.charAt(index + source.length())) >= 0) return true;
        }
        return false;
    }

    public static class TextBlock {
        String original, current, modelCorrected, exp = "";
        boolean isMutable, userModified;
        float conf;
        int type;
        public TextBlock(String original, String current, boolean mutable, float confidence, int type) {
            this.original = original; this.current = original != null && original.equals(current) ? original : current; this.modelCorrected = this.current; this.isMutable = mutable; this.conf = confidence; this.type = type;
        }
    }
    public static class TargetSpan { String expected; TargetSpan(String expected) { this.expected = expected; } }
    public static class ListMarkerSpan {}
    public static class ClauseLink { ListMarkerSpan listMarkerSpan; List<TargetSpan> targetSpans = new ArrayList<>(); int targetOffset = -1; boolean isDead; }
    public abstract static class JumpSpan extends ClickableSpan { public int getTargetOffset(Spanned text) { return -1; } }
    public abstract static class EditSpan extends ClickableSpan {}
    public static class IgnoredInCopySpan extends android.text.style.CharacterStyle { @Override public void updateDrawState(TextPaint paint) {} }

    public static class MyLinkMovementMethod extends LinkMovementMethod {
        private static final MyLinkMovementMethod INSTANCE = new MyLinkMovementMethod();
        public static MyLinkMovementMethod getInstance() { return INSTANCE; }
        @Override public boolean onTouchEvent(TextView widget, Spannable buffer, MotionEvent event) {
            int action = event.getActionMasked();
            if (action == MotionEvent.ACTION_UP || action == MotionEvent.ACTION_DOWN) {
                int x = (int) event.getX() - widget.getTotalPaddingLeft() + widget.getScrollX();
                int y = (int) event.getY() - widget.getTotalPaddingTop() + widget.getScrollY();
                Layout layout = widget.getLayout();
                if (layout != null) {
                    int line = layout.getLineForVertical(y), offset = layout.getOffsetForHorizontal(line, x);
                    ClickableSpan[] links = buffer.getSpans(offset, offset, ClickableSpan.class);
                    if (links.length > 0) { if (action == MotionEvent.ACTION_UP) links[0].onClick(widget); return true; }
                }
            }
            return super.onTouchEvent(widget, buffer, event);
        }
    }

    public static class WavyUnderlineSpan extends android.text.style.ReplacementSpan {
        public final int color;
        private final android.graphics.Paint wavePaint = new android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG);
        private final android.graphics.Path wavePath = new android.graphics.Path();
        private float cachedWidth = -1f, textWidth = -1f;
        WavyUnderlineSpan(int color) { this.color = color; wavePaint.setColor(color); wavePaint.setStyle(android.graphics.Paint.Style.STROKE); wavePaint.setStrokeWidth(3.5f); }
        @Override public int getSize(android.graphics.Paint paint, CharSequence text, int start, int end, android.graphics.Paint.FontMetricsInt fm) { textWidth = paint.measureText(text, start, end); return (int) textWidth; }
        @Override public void draw(android.graphics.Canvas canvas, CharSequence text, int start, int end, float x, int top, int y, int bottom, android.graphics.Paint paint) {
            canvas.drawText(text, start, end, x, y, paint);
            float width = textWidth > 0 ? textWidth : paint.measureText(text, start, end);
            if (cachedWidth != width) {
                cachedWidth = width; wavePath.reset(); float waveLength = 12f, amplitude = 2.5f, currentY = paint.getFontMetrics().descent + 3; wavePath.moveTo(0, currentY);
                for (float i = 0; i < width; i += waveLength) {
                    float next = Math.min(i + waveLength, width); wavePath.quadTo(i + waveLength / 4, currentY - amplitude, i + waveLength / 2, currentY); wavePath.quadTo(i + waveLength * 3 / 4, currentY + amplitude, next, currentY);
                }
            }
            int save = canvas.save(); canvas.translate(x, y); canvas.drawPath(wavePath, wavePaint); canvas.restoreToCount(save);
        }
    }

    public static class ColoredStrikethroughSpan extends android.text.style.ReplacementSpan {
        public final int textColor, lineColor; private float cachedWidth = -1f;
        ColoredStrikethroughSpan(int textColor, int lineColor) { this.textColor = textColor; this.lineColor = lineColor; }
        @Override public int getSize(android.graphics.Paint paint, CharSequence text, int start, int end, android.graphics.Paint.FontMetricsInt fm) { cachedWidth = paint.measureText(text, start, end); return (int) cachedWidth; }
        @Override public void draw(android.graphics.Canvas canvas, CharSequence text, int start, int end, float x, int top, int y, int bottom, android.graphics.Paint paint) {
            int oldColor = paint.getColor(); float oldStroke = paint.getStrokeWidth(); android.graphics.Paint.Style oldStyle = paint.getStyle();
            paint.setColor(textColor); canvas.drawText(text, start, end, x, y, paint);
            paint.setColor(lineColor); paint.setStyle(android.graphics.Paint.Style.STROKE); paint.setStrokeWidth(paint.getTextSize() / 14f);
            float width = cachedWidth > 0 ? cachedWidth : paint.measureText(text, start, end); canvas.drawLine(x, y - paint.getTextSize() * 0.3f, x + width, y - paint.getTextSize() * 0.3f, paint);
            paint.setColor(oldColor); paint.setStrokeWidth(oldStroke); paint.setStyle(oldStyle);
        }
    }

    public static class EditorState {
        SpannableStringBuilder text; int selectionStart;
        EditorState(SpannableStringBuilder text, int selectionStart) { this.text = text; this.selectionStart = selectionStart; }
    }

    public static List<TextBlock> mergeNormalBlocks(List<TextBlock> blocks) {
        List<TextBlock> result = new ArrayList<>(); StringBuilder original = new StringBuilder(), current = new StringBuilder();
        for (TextBlock block : blocks) {
            if (block.type == 0 && !block.isMutable) { original.append(block.original); current.append(block.current); }
            else {
                if (original.length() > 0) { result.add(new TextBlock(original.toString(), current.toString(), false, 0f, 0)); original.setLength(0); current.setLength(0); }
                result.add(block);
            }
        }
        if (original.length() > 0) result.add(new TextBlock(original.toString(), current.toString(), false, 0f, 0));
        return result;
    }

    public static String escapeHtmlQuick(String text) {
        if (text == null) return "";
        StringBuilder result = new StringBuilder(text.length() + 16);
        for (int i = 0; i < text.length(); i++) { char c = text.charAt(i); if (c == '&') result.append("&amp;"); else if (c == '<') result.append("&lt;"); else if (c == '>') result.append("&gt;"); else result.append(c); }
        return result.toString();
    }

    private static void appendLiveHtmlText(StringBuilder result, String text) {
        for (int i = 0; i < text.length(); i++) { char c = text.charAt(i); if (c == '&') result.append("&amp;"); else if (c == '<') result.append("&lt;"); else if (c == '>') result.append("&gt;"); else if (c == '\n') result.append("<br>"); else result.append(c); }
    }

    public static String getCleanTextStatic() {
        StringBuilder result = new StringBuilder();
        for (List<TextBlock> sentence : allSentencesBlocks) for (TextBlock block : sentence) result.append(block.current);
        return result.toString();
    }

    public static String extractCleanTextFromSpanned(Spanned text) {
        if (text == null) return "";
        IgnoredInCopySpan[] spans = text.getSpans(0, text.length(), IgnoredInCopySpan.class);
        if (spans.length == 0) return text.toString();
        List<int[]> ranges = new ArrayList<>(spans.length);
        for (IgnoredInCopySpan span : spans) {
            int start = text.getSpanStart(span), end = text.getSpanEnd(span);
            if (start >= 0 && end > start) ranges.add(new int[]{start, end});
        }
        ranges.sort(Comparator.comparingInt(a -> a[0]));
        StringBuilder result = new StringBuilder(text.length()); int cursor = 0;
        for (int[] range : ranges) {
            if (range[0] > cursor) result.append(text, cursor, range[0]); cursor = Math.max(cursor, range[1]);
        }
        if (cursor < text.length()) result.append(text, cursor, text.length());
        return result.toString();
    }

    public static String serializeBlocks(List<List<TextBlock>> blocks) {
        JSONArray outer = new JSONArray();
        try {
            for (List<TextBlock> sentence : blocks) {
                JSONArray inner = new JSONArray();
                for (TextBlock block : sentence) {
                    JSONObject object = new JSONObject(); object.put("o", block.original); object.put("c", block.current); object.put("mc", block.modelCorrected); object.put("m", block.isMutable); object.put("f", block.conf); object.put("t", block.type); object.put("u", block.userModified); if (block.exp != null && !block.exp.isEmpty()) object.put("exp", block.exp); inner.put(object);
                }
                outer.put(inner);
            }
        } catch (Exception ignored) {}
        return outer.toString();
    }

    public static List<List<TextBlock>> deserializeBlocks(String json) {
        List<List<TextBlock>> result = new ArrayList<>();
        try {
            JSONArray outer = new JSONArray(json);
            for (int i = 0; i < outer.length(); i++) {
                JSONArray inner = outer.getJSONArray(i); List<TextBlock> sentence = new ArrayList<>();
                for (int j = 0; j < inner.length(); j++) {
                    JSONObject object = inner.getJSONObject(j); TextBlock block = new TextBlock(object.getString("o"), object.getString("c"), object.getBoolean("m"), (float) object.getDouble("f"), object.getInt("t")); block.modelCorrected = object.getString("mc"); block.userModified = object.getBoolean("u"); block.exp = object.optString("exp", ""); sentence.add(block);
                }
                result.add(sentence);
            }
        } catch (Exception ignored) {}
        return result;
    }

    public static String serializeSpannable(Spannable text) {
        if (text == null) return "";
        try {
            JSONObject root = new JSONObject(); root.put("text", text.toString()); JSONArray array = new JSONArray();
            for (Object span : text.getSpans(0, text.length(), Object.class)) {
                JSONObject object = new JSONObject(); object.put("start", text.getSpanStart(span)); object.put("end", text.getSpanEnd(span)); object.put("flags", text.getSpanFlags(span));
                if (span instanceof ForegroundColorSpan) { object.put("type", "ForegroundColorSpan"); object.put("color", ((ForegroundColorSpan) span).getForegroundColor()); }
                else if (span instanceof android.text.style.StyleSpan) { object.put("type", "StyleSpan"); object.put("style", ((android.text.style.StyleSpan) span).getStyle()); }
                else if (span instanceof WavyUnderlineSpan) { object.put("type", "WavyUnderlineSpan"); object.put("color", ((WavyUnderlineSpan) span).color); }
                else if (span instanceof ColoredStrikethroughSpan) { object.put("type", "ColoredStrikethroughSpan"); object.put("textColor", ((ColoredStrikethroughSpan) span).textColor); object.put("lineColor", ((ColoredStrikethroughSpan) span).lineColor); }
                else if (span instanceof StrikethroughSpan) object.put("type", "StrikethroughSpan");
                else if (span instanceof android.text.style.RelativeSizeSpan) { object.put("type", "RelativeSizeSpan"); object.put("size", ((android.text.style.RelativeSizeSpan) span).getSizeChange()); }
                else if (span instanceof JumpSpan) { int target = ((JumpSpan) span).getTargetOffset(text); if (target < 0) continue; object.put("type", "JumpSpan"); object.put("target", target); }
                else if (span instanceof IgnoredInCopySpan) object.put("type", "IgnoredInCopySpan"); else continue;
                array.put(object);
            }
            root.put("spans", array); return root.toString();
        } catch (Exception ignored) { return ""; }
    }

    public static SpannableStringBuilder deserializeSpannable(String json) {
        if (json == null || json.isEmpty()) return null;
        try {
            JSONObject root = new JSONObject(json); String value = root.getString("text"); SpannableStringBuilder result = new SpannableStringBuilder(value); JSONArray array = root.getJSONArray("spans");
            for (int i = 0; i < array.length(); i++) {
                JSONObject object = array.getJSONObject(i); int start = object.getInt("start"), end = object.getInt("end"), flags = object.getInt("flags"); String type = object.getString("type"); Object span = null;
                if ("ForegroundColorSpan".equals(type)) span = new ForegroundColorSpan(object.getInt("color"));
                else if ("StyleSpan".equals(type)) span = new android.text.style.StyleSpan(object.getInt("style"));
                else if ("WavyUnderlineSpan".equals(type)) span = new WavyUnderlineSpan(object.getInt("color"));
                else if ("ColoredStrikethroughSpan".equals(type)) span = new ColoredStrikethroughSpan(object.getInt("textColor"), object.getInt("lineColor"));
                else if ("StrikethroughSpan".equals(type)) span = new StrikethroughSpan();
                else if ("RelativeSizeSpan".equals(type)) span = new android.text.style.RelativeSizeSpan((float) object.getDouble("size"));
                else if ("IgnoredInCopySpan".equals(type)) span = new IgnoredInCopySpan();
                else if ("JumpSpan".equals(type)) {
                    int target = object.getInt("target");
                    span = createPortableJumpSpan(target);
                }
                if (span != null && start >= 0 && start <= end && end <= value.length()) result.setSpan(span, start, end, flags);
            }
            return result;
        } catch (Exception ignored) { return null; }
    }

    private static JumpSpan createPortableJumpSpan(int target) {
        return new JumpSpan() {
            @Override public int getTargetOffset(Spanned text) { return target; }
            @Override public void onClick(View view) { if (view instanceof TextView) jumpAndFlash((TextView) view, target, null); }
            @Override public void updateDrawState(TextPaint paint) { paint.setColor(0xFF2196F3); paint.setUnderlineText(true); paint.setTypeface(android.graphics.Typeface.create("sans-serif-medium", 0)); }
        };
    }

    private static void normalizePortableJumpSpans(SpannableStringBuilder text) {
        if (text == null) return;
        JumpSpan[] spans = text.getSpans(0, text.length(), JumpSpan.class);
        for (JumpSpan old : spans) {
            int start = text.getSpanStart(old), end = text.getSpanEnd(old), flags = text.getSpanFlags(old);
            int target = old.getTargetOffset(text);
            text.removeSpan(old);
            if (start >= 0 && end >= start && end <= text.length() && target >= 0 && target <= text.length())
                text.setSpan(createPortableJumpSpan(target), start, end, flags);
        }
    }

    // 普通输出框需要固定偏移的便携 JumpSpan；重新进入便签后再恢复为会随正文编辑移动的动态锚点。
    // 这样“编辑 -> 收起 -> 再打开 -> 再编辑”时，前方增删文字不会让序号仍跳到上一次的旧坐标。
    private void rebindPortableJumpsForEditor(Editable text) {
        if (text == null) return;
        JumpSpan[] jumps = text.getSpans(0, text.length(), JumpSpan.class);
        if (jumps.length == 0) { currentClauseLinks.clear(); return; }

        // 旧的动态标记可能来自上一次便签会话；便携 JumpSpan 已保存了当时的正确绝对位置，
        // 因此以它为唯一基准重建，避免重复锚点或旧 ClauseLink 干扰。
        for (TargetSpan target : text.getSpans(0, text.length(), TargetSpan.class)) text.removeSpan(target);
        for (ListMarkerSpan marker : text.getSpans(0, text.length(), ListMarkerSpan.class)) text.removeSpan(marker);
        currentClauseLinks.clear();

        for (JumpSpan old : jumps) {
            int markerStart = text.getSpanStart(old), markerEnd = text.getSpanEnd(old), flags = text.getSpanFlags(old);
            int targetOffset = old.getTargetOffset(text);
            text.removeSpan(old);
            if (markerStart < 0 || markerEnd < markerStart || markerEnd > text.length() || targetOffset < 0 || targetOffset > text.length()) continue;

            // 正常纠错目标都指向正文中的实际字符。极端情况下若目标正好在末尾，锚定前一个字符。
            int anchorStart = targetOffset;
            if (anchorStart == text.length() && anchorStart > 0) anchorStart--;
            if (anchorStart < 0 || anchorStart >= text.length()) {
                // 空文本等极端情况仍保留可点击序号，但没有可跟随的正文锚点。
                text.setSpan(createPortableJumpSpan(targetOffset), markerStart, markerEnd, flags);
                continue;
            }
            int anchorEnd = Math.min(text.length(), anchorStart + Character.charCount(Character.codePointAt(text, anchorStart)));
            String expected = text.subSequence(anchorStart, anchorEnd).toString();

            ClauseLink link = new ClauseLink();
            ListMarkerSpan marker = new ListMarkerSpan();
            TargetSpan target = new TargetSpan(expected);
            link.listMarkerSpan = marker;
            link.targetSpans.add(target);
            text.setSpan(marker, markerStart, markerEnd, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
            text.setSpan(target, anchorStart, anchorEnd, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);

            JumpSpan dynamic = new JumpSpan() {
                @Override public int getTargetOffset(Spanned current) {
                    if (link.isDead) return -1;
                    for (TargetSpan target : link.targetSpans) {
                        int start = current.getSpanStart(target);
                        if (start >= 0 && start <= current.length()) return start;
                    }
                    return -1;
                }
                @Override public void onClick(View view) {
                    if (!(view instanceof TextView)) return;
                    TextView textView = (TextView) view;
                    CharSequence value = textView.getText();
                    if (!(value instanceof Spanned)) return;
                    int target = getTargetOffset((Spanned) value);
                    if (target >= 0) jumpEditorToOffset(textView, target);
                }
                @Override public void updateDrawState(TextPaint paint) {
                    paint.setColor(0xFF2196F3); paint.setUnderlineText(true); paint.setTypeface(android.graphics.Typeface.create("sans-serif-medium", 0));
                }
            };
            text.setSpan(dynamic, markerStart, markerEnd, flags);
            currentClauseLinks.add(link);
        }
    }

    private static void jumpAndFlash(TextView textView, int offset, ScrollView preferred) {
        try {
            Spannable text = (Spannable) textView.getText(); if (offset < 0 || offset > text.length()) return; Layout layout = textView.getLayout(); if (layout == null) return;
            int line = layout.getLineForOffset(offset), lineStart = layout.getLineStart(line), lineEnd = layout.getLineEnd(line), y = layout.getLineTop(line);
            ScrollView scroll = preferred;
            if (scroll == null) {
                android.content.Context context = textView.getContext();
                while (context instanceof android.content.ContextWrapper && !(context instanceof android.app.Activity))
                    context = ((android.content.ContextWrapper) context).getBaseContext();
                if (context instanceof android.app.Activity) {
                    android.app.Activity activity = (android.app.Activity) context;
                    scroll = activity.findViewById(textView.getId() == R.id.expandedEditText ? R.id.editorScrollView : R.id.scrollView);
                }
            }
            if (scroll != null) scroll.scrollTo(0, Math.max(0, y - scroll.getHeight() / 3));
            BackgroundColorSpan flash = new BackgroundColorSpan(0x609E9E9E); Handler handler = AppExecutors.MAIN;
            Runnable add = () -> { if (lineStart >= 0 && lineEnd <= text.length()) { text.setSpan(flash, lineStart, lineEnd, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE); textView.invalidate(); } };
            Runnable remove = () -> { text.removeSpan(flash); textView.invalidate(); };
            add.run(); handler.postDelayed(remove, 500); handler.postDelayed(add, 800); handler.postDelayed(remove, 1300);
        } catch (Exception ignored) {}
    }

    public static void ensureTypoMapLoaded(Context context) {
        if (typoMapLoaded) return;
        synchronized (MainActivity.class) {
            if (!typoMapLoaded) loadTypoMap(context);
        }
    }

    public static synchronized void loadTypoMap(Context context) {
        Map<String, String> words = new HashMap<>(); Set<String> customs = new HashSet<>();
        Map<String, String[]> exclusions = new HashMap<>();
        String dictionaryText=SecureAsset.readUtf8(context,"sys_typo.dat");
        if(dictionaryText==null||dictionaryText.isEmpty())throw new IllegalStateException("错词库读取失败："+SecureAsset.lastErrorSummary());
        try (BufferedReader reader = new BufferedReader(new java.io.StringReader(dictionaryText))) {
            String line;
            while ((line = reader.readLine()) != null) parseTypoLine(line, words, exclusions);
        } catch (Exception error) { throw new IllegalStateException("错词库加载失败",error); }
        // 内置白名单：匹配整词后保护其中的五字，不截断前面开始的更长错词；用户白名单另有跨词保护。
        for (String word : new String[]{"舒的", "怎的", "能的", "您的", "得得得", "得吃", "得逞", "说的", "折射得"}) { words.put(word, word); exclusions.remove(word); }
        try {
            JSONObject custom = new JSONObject(context.getSharedPreferences("DededeConfig", MODE_PRIVATE).getString("custom_typos", "{}")); Iterator<String> keys = custom.keys();
            while (keys.hasNext()) { String source = keys.next(); if (source.isEmpty()) continue;
                words.put(source, custom.getString(source)); customs.add(source); exclusions.remove(source); }
        } catch (Exception error) { throw new IllegalStateException("错词库加载失败",error); }
        typoIndex = TypoIndex.build(words, customs, exclusions);
        typoMapLoaded = true;
    }

    static void parseTypoLine(String line, Map<String, String> words, Map<String, String[]> exclusions) {
        line = line.trim(); if (line.startsWith("\uFEFF")) line = line.substring(1).trim();
        if (line.isEmpty()) return;
        String[] fields = TYPO_FIELDS.split(line, 3);
        if (fields.length < 2 || fields[0].equals(fields[1])) return;
        words.put(fields[0], fields[1]); exclusions.remove(fields[0]);
        if (fields.length == 3 && fields[2].startsWith("n=")) {
            String tail = fields[2].substring(2).trim();
            if (!tail.isEmpty()) exclusions.put(fields[0], TYPO_FIELDS.split(tail));
        }
        String[] boundaryExceptions = null;
        if ("妨照".equals(fields[0]) && "仿照".equals(fields[1])) boundaryExceptions = new String[]{"不妨照"};
        if ("换界".equals(fields[0]) && "换届".equals(fields[1])) boundaryExceptions = new String[]{"换界面"};
        if ("做数".equals(fields[0]) && "作数".equals(fields[1])) boundaryExceptions = new String[]{"做数学", "做数据", "做数值", "做数理", "做数独", "做数字", "做数量", "做数组"};
        if (boundaryExceptions != null) {
            java.util.LinkedHashSet<String> merged = new java.util.LinkedHashSet<>();
            String[] existing = exclusions.get(fields[0]); if (existing != null) Collections.addAll(merged, existing);
            Collections.addAll(merged, boundaryExceptions); exclusions.put(fields[0], merged.toArray(new String[0]));
        }

    }
    private static void reloadTypoMapAsync(Context context) {
        Context app = context.getApplicationContext(); AppExecutors.INFERENCE.execute(() -> {try{loadTypoMap(app);}catch(Throwable error){showModelError(errorDetails(error));}});
    }

    private static volatile TextRecognizer textRecognizer;
    private static final Object OCR_LOCK = new Object();
    private static final Pattern PUNCT_PATTERN_1 = Pattern.compile("(?<=[\\u4e00-\\u9fa5])\\.{2,6}(?=[\\u4e00-\\u9fa5]?)");
    private static final Pattern PUNCT_PATTERN_2 = Pattern.compile("(?<=[\\u4e00-\\u9fa5]?)\\.{2,6}(?=[\\u4e00-\\u9fa5])");
    private static final Pattern WORD_TEXT_PATTERN = Pattern.compile("<w:t[^>]*>(.*?)</w:t>", Pattern.DOTALL);
    private static final Pattern PPT_TEXT_PATTERN = Pattern.compile("<a:t[^>]*>(.*?)</a:t>", Pattern.DOTALL);

    private static final ThreadLocal<String> lastExtractError = new ThreadLocal<String>() { @Override protected String initialValue() { return ""; } };
    private static final long OCR_TIMEOUT_SECONDS = 120L;
    private static final long MAX_OCR_PIXELS = 20_000_000L;
    private static final int OCR_SINGLE_PASS_MAX_HEIGHT = 4200;
    private static final long OCR_SINGLE_PASS_MAX_PIXELS = 12_000_000L;
    private static final int OCR_TARGET_CORE_HEIGHT = 2800;
    private static final int OCR_MIN_CORE_HEIGHT = 1200;
    private static final int OCR_CHUNK_OVERLAP = 320;
    private static final int OCR_SPLIT_SEARCH_RADIUS = 420;
    private static final long MAX_PDF_RENDER_PIXELS = 12_000_000L;

    private static final class OcrLineResult {
        final String text;
        final int left;
        final int top;
        final int right;
        final int bottom;

        OcrLineResult(String text, int left, int top, int right, int bottom) {
            this.text = text;
            this.left = left;
            this.top = top;
            this.right = right;
            this.bottom = bottom;
        }

        int centerY() {
            return top + Math.max(0, bottom - top) / 2;
        }
    }

    private static TextRecognizer getTextRecognizer() {
        TextRecognizer local = textRecognizer;
        if (local == null) synchronized (OCR_LOCK) {
            local = textRecognizer;
            if (local == null) textRecognizer = local = TextRecognition.getClient(new ChineseTextRecognizerOptions.Builder().build());
        }
        return local;
    }

    public static String getLastExtractError() { return lastExtractError.get(); }

    private static String describeExtractError(Throwable throwable) {
        Throwable root = throwable;
        while (root.getCause() != null && root.getCause() != root) root = root.getCause();
        String message = root.getMessage();
        String name = root.getClass().getSimpleName();
        if (message == null || message.trim().isEmpty()) return name;
        message = message.replace('\n', ' ').replace('\r', ' ').trim();
        return name + "：" + (message.length() > 120 ? message.substring(0, 120) + "…" : message);
    }

    private static String recognizeInputImage(InputImage image) throws Exception {
        synchronized (OCR_LOCK) {
            try {
                Text result = Tasks.await(getTextRecognizer().process(image), OCR_TIMEOUT_SECONDS, java.util.concurrent.TimeUnit.SECONDS);
                return result == null ? "" : result.getText();
            } catch (java.util.concurrent.ExecutionException exception) {
                Throwable cause = exception.getCause() == null ? exception : exception.getCause();
                throw new Exception("ML Kit识别失败：" + describeExtractError(cause), cause);
            } catch (java.util.concurrent.TimeoutException exception) {
                throw new Exception("OCR识别超时，请尝试较小的图片或PDF", exception);
            }
        }
    }

    private static List<OcrLineResult> recognizeInputImageLines(InputImage image, int globalOffsetY, int fallbackCenterY) throws Exception {
        synchronized (OCR_LOCK) {
            try {
                Text result = Tasks.await(getTextRecognizer().process(image), OCR_TIMEOUT_SECONDS, java.util.concurrent.TimeUnit.SECONDS);
                List<OcrLineResult> lines = new ArrayList<>();
                if (result == null) return lines;

                for (Text.TextBlock block : result.getTextBlocks()) {
                    android.graphics.Rect blockBox = block.getBoundingBox();
                    for (Text.Line line : block.getLines()) {
                        String value = line.getText();
                        if (value == null || value.trim().isEmpty()) continue;
                        android.graphics.Rect box = line.getBoundingBox();
                        if (box == null) box = blockBox;
                        if (box == null) {
                            lines.add(new OcrLineResult(value, 0, fallbackCenterY, 0, fallbackCenterY + 1));
                        } else {
                            lines.add(new OcrLineResult(
                                    value,
                                    box.left,
                                    globalOffsetY + box.top,
                                    box.right,
                                    globalOffsetY + box.bottom
                            ));
                        }
                    }
                }
                return lines;
            } catch (java.util.concurrent.ExecutionException exception) {
                Throwable cause = exception.getCause() == null ? exception : exception.getCause();
                throw new Exception("ML Kit识别失败：" + describeExtractError(cause), cause);
            } catch (java.util.concurrent.TimeoutException exception) {
                throw new Exception("OCR识别超时，请尝试较小的图片或PDF", exception);
            }
        }
    }

    private static Bitmap decodeBitmapFromUri(Context context, android.net.Uri uri) throws Exception {
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.P) {
            android.graphics.ImageDecoder.Source source = android.graphics.ImageDecoder.createSource(context.getContentResolver(), uri);
            Bitmap bitmap = android.graphics.ImageDecoder.decodeBitmap(source, (decoder, info, src) -> {
                decoder.setAllocator(android.graphics.ImageDecoder.ALLOCATOR_SOFTWARE);
                int width = info.getSize().getWidth(), height = info.getSize().getHeight();
                long pixels = (long) width * height;
                if (pixels > MAX_OCR_PIXELS) {
                    double scale = Math.sqrt((double) MAX_OCR_PIXELS / pixels);
                    decoder.setTargetSize(Math.max(1, (int) Math.round(width * scale)), Math.max(1, (int) Math.round(height * scale)));
                }
            });
            if (bitmap == null) throw new IOException("图片解码结果为空");
            return bitmap;
        }

        android.graphics.BitmapFactory.Options bounds = new android.graphics.BitmapFactory.Options();
        bounds.inJustDecodeBounds = true;
        try (InputStream input = context.getContentResolver().openInputStream(uri)) {
            if (input == null) throw new IOException("无法打开图片文件");
            android.graphics.BitmapFactory.decodeStream(input, null, bounds);
        }
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) throw new IOException("无法读取图片尺寸");
        int sample = 1;
        while ((long) Math.max(1, bounds.outWidth / sample) * Math.max(1, bounds.outHeight / sample) > MAX_OCR_PIXELS) sample <<= 1;
        android.graphics.BitmapFactory.Options options = new android.graphics.BitmapFactory.Options();
        options.inSampleSize = sample;
        options.inPreferredConfig = Bitmap.Config.ARGB_8888;
        try (InputStream input = context.getContentResolver().openInputStream(uri)) {
            if (input == null) throw new IOException("无法重新打开图片文件");
            Bitmap bitmap = android.graphics.BitmapFactory.decodeStream(input, null, options);
            if (bitmap == null) throw new IOException("图片格式不受支持或文件已损坏");
            return bitmap;
        }
    }

    public static String extractTextFromUriSync(Context context, android.net.Uri uri, TextExtractCallback callback) {
        Bitmap bitmap = null;
        lastExtractError.set("");
        try {
            if (uri == null) throw new IOException("文件地址为空");
            String mime = context.getContentResolver().getType(uri), name = getFileName(context, uri); if (name != null) name = name.toLowerCase(Locale.ROOT);
            if ((name != null && (name.endsWith(".jpg") || name.endsWith(".jpeg") || name.endsWith(".png") || name.endsWith(".bmp") || name.endsWith(".webp") || name.endsWith(".heic") || name.endsWith(".heif"))) || (mime != null && mime.startsWith("image/"))) {
                synchronized (OCR_LOCK) {
                bitmap = decodeBitmapFromUri(context, uri);
                String result = performOcrOnBitmap(bitmap, context, callback);
                if (result == null || result.trim().isEmpty()) lastExtractError.set("图片读取成功，但没有识别到文字");
                return result == null ? "" : result;
                }
            }
            if ((name != null && name.endsWith(".pdf")) || "application/pdf".equals(mime)) {
                synchronized (OCR_LOCK) {
                String result = performOcrOnPdf(uri, context, callback);
                if (result == null || result.trim().isEmpty()) lastExtractError.set("PDF读取成功，但没有识别到文字");
                return result == null ? "" : result;
                }
            }
            String result = extractTextFromUri(context, uri);
            if (result == null || result.trim().isEmpty()) lastExtractError.set("文件内容为空或格式不受支持");
            return result == null ? "" : result;
        } catch (Throwable throwable) {
            if (throwable instanceof ThreadDeath) throw (ThreadDeath) throwable;
            lastExtractError.set(describeExtractError(throwable));
            android.util.Log.e("DededeOCR", "文件识别失败: " + uri, throwable);
            return "";
        } finally { if (bitmap != null && !bitmap.isRecycled()) bitmap.recycle(); }
    }

    public static String cleanOcrText(String text) {
        if (text == null) return "";
        String[] lines = text.split("\n", -1); StringBuilder result = new StringBuilder(text.length()); boolean first = true;
        for (String line : lines) {
            String trimmed = line.trim();
            if (trimmed.length() == 1 && "个口日目一丨丶卜丿〇回凸凹卐卍了的地得".contains(trimmed)) continue;
            if (!first) result.append('\n'); result.append(line); first = false;
        }
        return result.toString();
    }

    private static int countDarkSamples(Bitmap bitmap, int y, int[] row) {
        int width = bitmap.getWidth();
        bitmap.getPixels(row, 0, width, 0, y, width, 1);
        int step = Math.max(1, width / 96);
        int darkCount = 0;
        for (int x = 0; x < width; x += step) {
            int color = row[x];
            if (Color.alpha(color) < 32) continue;
            int luminance = (Color.red(color) * 299 + Color.green(color) * 587 + Color.blue(color) * 114) / 1000;
            if (luminance < 215) darkCount++;
        }
        return darkCount;
    }

    private static int findBestOcrSplit(Bitmap bitmap, int coreStart, int idealEnd) {
        int imageHeight = bitmap.getHeight();
        int searchStart = Math.max(coreStart + OCR_MIN_CORE_HEIGHT, idealEnd - OCR_SPLIT_SEARCH_RADIUS);
        int searchEnd = Math.min(imageHeight - OCR_MIN_CORE_HEIGHT, idealEnd + OCR_SPLIT_SEARCH_RADIUS);
        if (searchStart >= searchEnd) return idealEnd;

        int width = bitmap.getWidth();
        int[] row = new int[width];
        int step = Math.max(1, width / 96);
        int sampleCount = Math.max(1, (width + step - 1) / step);
        int blankThreshold = Math.max(1, sampleCount / 40);
        int bestLowDensityRow = idealEnd;
        long bestLowDensityScore = Long.MAX_VALUE;
        int blankRunStart = -1;
        int bestBlankStart = -1;
        int bestBlankEnd = -1;

        for (int y = searchStart; y <= searchEnd; y += 2) {
            int dark = countDarkSamples(bitmap, y, row);
            long score = dark * 10_000L + Math.abs(y - idealEnd);
            if (score < bestLowDensityScore) {
                bestLowDensityScore = score;
                bestLowDensityRow = y;
            }
            if (dark <= blankThreshold) {
                if (blankRunStart < 0) blankRunStart = y;
            } else if (blankRunStart >= 0) {
                int blankRunEnd = y - 2;
                if (bestBlankStart < 0 || blankRunEnd - blankRunStart > bestBlankEnd - bestBlankStart) {
                    bestBlankStart = blankRunStart;
                    bestBlankEnd = blankRunEnd;
                }
                blankRunStart = -1;
            }
        }

        if (blankRunStart >= 0 && (bestBlankStart < 0 || searchEnd - blankRunStart > bestBlankEnd - bestBlankStart)) {
            bestBlankStart = blankRunStart;
            bestBlankEnd = searchEnd;
        }
        if (bestBlankStart >= 0 && bestBlankEnd - bestBlankStart >= 8) return (bestBlankStart + bestBlankEnd) / 2;
        return bestLowDensityRow;
    }

    private static List<Integer> buildOcrCoreBoundaries(Bitmap bitmap) {
        int imageHeight = bitmap.getHeight();
        List<Integer> boundaries = new ArrayList<>();
        boundaries.add(0);
        int coreStart = 0;

        while (imageHeight - coreStart > OCR_TARGET_CORE_HEIGHT) {
            int idealEnd = Math.min(imageHeight, coreStart + OCR_TARGET_CORE_HEIGHT);
            if (imageHeight - idealEnd < OCR_MIN_CORE_HEIGHT) break;
            int split = findBestOcrSplit(bitmap, coreStart, idealEnd);
            if (split <= coreStart + OCR_MIN_CORE_HEIGHT || split >= imageHeight) split = idealEnd;
            boundaries.add(split);
            coreStart = split;
        }

        if (boundaries.get(boundaries.size() - 1) != imageHeight) boundaries.add(imageHeight);
        return boundaries;
    }

    private static String joinOcrLines(List<OcrLineResult> lines) {
        StringBuilder result = new StringBuilder();
        for (OcrLineResult line : lines) {
            if (line.text == null || line.text.trim().isEmpty()) continue;
            if (result.length() > 0) result.append('\n');
            result.append(line.text);
        }
        return result.toString();
    }

    public static String performOcrOnBitmap(Bitmap fullBitmap, Context context, TextExtractCallback callback) throws Exception {
        if (fullBitmap == null || fullBitmap.isRecycled()) throw new IOException("图片位图不可用");
        long pixels = (long) fullBitmap.getWidth() * fullBitmap.getHeight();

        if (fullBitmap.getHeight() <= OCR_SINGLE_PASS_MAX_HEIGHT && pixels <= OCR_SINGLE_PASS_MAX_PIXELS) {
            if (callback != null) AppExecutors.MAIN.post(() -> callback.onProgress(1, 1));
            String value = recognizeInputImage(InputImage.fromBitmap(fullBitmap, 0));
            return cleanOcrText(fixPunctuation(value));
        }

        List<Integer> boundaries = buildOcrCoreBoundaries(fullBitmap);
        int total = boundaries.size() - 1;
        List<OcrLineResult> acceptedLines = new ArrayList<>();

        for (int i = 0; i < total; i++) {
            int progress = i + 1;
            if (callback != null) AppExecutors.MAIN.post(() -> callback.onProgress(progress, total));

            int coreStart = boundaries.get(i);
            int coreEnd = boundaries.get(i + 1);
            int cropStart = Math.max(0, coreStart - OCR_CHUNK_OVERLAP);
            int cropEnd = Math.min(fullBitmap.getHeight(), coreEnd + OCR_CHUNK_OVERLAP);
            int cropHeight = cropEnd - cropStart;
            if (cropHeight <= 0) continue;

            Bitmap chunk = Bitmap.createBitmap(fullBitmap, 0, cropStart, fullBitmap.getWidth(), cropHeight);
            try {
                List<OcrLineResult> chunkLines = recognizeInputImageLines(
                        InputImage.fromBitmap(chunk, 0),
                        cropStart,
                        coreStart + Math.max(0, coreEnd - coreStart) / 2
                );
                boolean firstChunk = i == 0;
                boolean lastChunk = i == total - 1;
                for (OcrLineResult line : chunkLines) {
                    int centerY = line.centerY();
                    boolean belongs = (firstChunk || centerY >= coreStart) && (lastChunk || centerY < coreEnd);
                    if (belongs) acceptedLines.add(line);
                }
            } finally {
                chunk.recycle();
            }
        }

        return cleanOcrText(fixPunctuation(joinOcrLines(acceptedLines)));
    }

    public static String performOcrOnPdf(android.net.Uri uri, Context context, TextExtractCallback callback) throws Exception {
        StringBuilder fullText = new StringBuilder();
        try (android.os.ParcelFileDescriptor descriptor = context.getContentResolver().openFileDescriptor(uri, "r")) {
            if (descriptor == null) return "";
            try (android.graphics.pdf.PdfRenderer renderer = new android.graphics.pdf.PdfRenderer(descriptor)) {
                int pages = renderer.getPageCount();
                for (int i = 0; i < pages; i++) {
                    int progress = i + 1;
                    if (callback != null) AppExecutors.MAIN.post(() -> callback.onProgress(progress, pages));
                    try (android.graphics.pdf.PdfRenderer.Page page = renderer.openPage(i)) {
                        long sourcePixels = Math.max(1L, (long) page.getWidth() * page.getHeight());
                        double scale = Math.min(2.0d, Math.sqrt((double) MAX_PDF_RENDER_PIXELS / sourcePixels));
                        if (!Double.isFinite(scale) || scale <= 0d) scale = 1d;
                        int renderWidth = Math.max(1, (int) Math.round(page.getWidth() * scale));
                        int renderHeight = Math.max(1, (int) Math.round(page.getHeight() * scale));
                        Bitmap bitmap = Bitmap.createBitmap(renderWidth, renderHeight, Bitmap.Config.ARGB_8888);
                        try {
                            bitmap.eraseColor(Color.WHITE);
                            android.graphics.Matrix matrix = new android.graphics.Matrix();
                            matrix.setScale(
                                    renderWidth / (float) Math.max(1, page.getWidth()),
                                    renderHeight / (float) Math.max(1, page.getHeight())
                            );
                            page.render(bitmap, null, matrix, android.graphics.pdf.PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY);
                            String pageText = performOcrOnBitmap(bitmap, context, null);
                            if (pageText != null && !pageText.isEmpty()) {
                                if (fullText.length() > 0) fullText.append("\n\n");
                                fullText.append(pageText);
                            }
                        } finally {
                            bitmap.recycle();
                        }
                    }
                }
            }
        }
        return cleanOcrText(fixPunctuation(fullText.toString()));
    }

    public static String fixPunctuation(String text) {
        if (text == null) return "";
        text = PUNCT_PATTERN_2.matcher(PUNCT_PATTERN_1.matcher(text).replaceAll("……")).replaceAll("……");
        StringBuilder result = new StringBuilder(text.length()); boolean inQuote = false;
        for (int i = 0; i < text.length(); i++) {
            char c = text.charAt(i); boolean punctuation = c == ',' || c == '.' || c == ':' || c == ';' || c == '?' || c == '!' || c == '"' || c == '(' || c == ')' || c == '\'';
            if (punctuation) {
                boolean previousChinese = false, nextChinese = false;
                for (int j = i - 1; j >= Math.max(0, i - 3); j--) { if (isChinese(text.charAt(j))) { previousChinese = true; break; } if (!Character.isWhitespace(text.charAt(j))) break; }
                for (int j = i + 1; j < Math.min(text.length(), i + 4); j++) { if (isChinese(text.charAt(j))) { nextChinese = true; break; } if (!Character.isWhitespace(text.charAt(j))) break; }
                if (previousChinese || nextChinese) {
                    if (c == ',') c = '，'; else if (c == '.') c = '。'; else if (c == ':') c = '：'; else if (c == ';') c = '；'; else if (c == '?') c = '？'; else if (c == '!') c = '！'; else if (c == '(') c = '（'; else if (c == ')') c = '）'; else if (c == '"') { c = inQuote ? '”' : '“'; inQuote = !inQuote; } else if (c == '\'') c = '’';
                }
            }
            result.append(c);
        }
        return result.toString();
    }

    public static boolean isChinese(char c) { return c >= '\u4e00' && c <= '\u9fa5'; }

    public static String extractTextFromUri(Context context, android.net.Uri uri) {
        String name = getFileName(context, uri), mime = context.getContentResolver().getType(uri); String lower = name == null ? "" : name.toLowerCase(Locale.ROOT);
        try {
            if (lower.endsWith(".docx") || "application/vnd.openxmlformats-officedocument.wordprocessingml.document".equals(mime)) return extractDocx(context, uri);
            if (lower.endsWith(".pptx") || "application/vnd.openxmlformats-officedocument.presentationml.presentation".equals(mime)) return extractPptx(context, uri);
            try (InputStream input = context.getContentResolver().openInputStream(uri); BufferedReader reader = new BufferedReader(new InputStreamReader(input, StandardCharsets.UTF_8))) {
                StringBuilder result = new StringBuilder(); String line; while ((line = reader.readLine()) != null) result.append(line).append('\n'); return result.toString();
            }
        } catch (Exception exception) { exception.printStackTrace(); return ""; }
    }

    private static String extractDocx(Context context, android.net.Uri uri) throws Exception {
        String xml = null;
        try (java.util.zip.ZipInputStream zip = new java.util.zip.ZipInputStream(context.getContentResolver().openInputStream(uri))) {
            java.util.zip.ZipEntry entry; byte[] buffer = new byte[8192];
            while ((entry = zip.getNextEntry()) != null) if ("word/document.xml".equals(entry.getName())) {
                ByteArrayOutputStream output = new ByteArrayOutputStream(); int read; while ((read = zip.read(buffer)) != -1) output.write(buffer, 0, read); xml = output.toString(StandardCharsets.UTF_8.name()); break;
            }
        }
        if (xml == null) return ""; StringBuilder result = new StringBuilder();
        try {
            org.xmlpull.v1.XmlPullParser parser = org.xmlpull.v1.XmlPullParserFactory.newInstance().newPullParser(); parser.setInput(new java.io.StringReader(xml)); boolean inText = false;
            for (int event = parser.getEventType(); event != org.xmlpull.v1.XmlPullParser.END_DOCUMENT; event = parser.next()) {
                String tag = parser.getName();
                if (event == org.xmlpull.v1.XmlPullParser.START_TAG && ("t".equals(tag) || "w:t".equals(tag))) inText = true;
                else if (event == org.xmlpull.v1.XmlPullParser.TEXT && inText) result.append(parser.getText());
                else if (event == org.xmlpull.v1.XmlPullParser.END_TAG) { if ("t".equals(tag) || "w:t".equals(tag)) inText = false; else if ("p".equals(tag) || "w:p".equals(tag)) result.append('\n'); }
            }
        } catch (Exception ignored) { result.setLength(0); Matcher matcher = WORD_TEXT_PATTERN.matcher(xml); while (matcher.find()) result.append(matcher.group(1)); return decodeXmlEntities(result.toString()); }
        return result.toString();
    }

    private static String extractPptx(Context context, android.net.Uri uri) throws Exception {
        StringBuilder result = new StringBuilder();
        try (java.util.zip.ZipInputStream zip = new java.util.zip.ZipInputStream(context.getContentResolver().openInputStream(uri))) {
            java.util.zip.ZipEntry entry; byte[] buffer = new byte[8192];
            while ((entry = zip.getNextEntry()) != null) if (entry.getName().startsWith("ppt/slides/slide") && entry.getName().endsWith(".xml")) {
                ByteArrayOutputStream output = new ByteArrayOutputStream(); int read; while ((read = zip.read(buffer)) != -1) output.write(buffer, 0, read);
                Matcher matcher = PPT_TEXT_PATTERN.matcher(output.toString(StandardCharsets.UTF_8.name())); while (matcher.find()) result.append(matcher.group(1)); result.append("\n\n");
            }
        }
        return decodeXmlEntities(result.toString()).trim();
    }

    private static String decodeXmlEntities(String text) {
        if (text.indexOf('&') < 0) return text;
        return text.replace("&lt;", "<").replace("&gt;", ">").replace("&quot;", "\"").replace("&apos;", "'").replace("&amp;", "&");
    }

    public static String getFileName(Context context, android.net.Uri uri) {
        String result = null;
        if (uri != null && "content".equals(uri.getScheme())) {
            try (android.database.Cursor cursor = context.getContentResolver().query(uri, null, null, null, null)) {
                if (cursor != null && cursor.moveToFirst()) { int index = cursor.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME); if (index >= 0) result = cursor.getString(index); }
            } catch (Exception ignored) {}
        }
        if (result == null && uri != null) { String path = uri.getPath(); if (path != null) { int cut = path.lastIndexOf('/'); result = cut >= 0 ? path.substring(cut + 1) : path; } }
        return result;
    }

    private EditText inputText, editTemp, editThreshDe1, editThreshDe2, editThreshDe3, editThreshZuo, editThreshZuo4, expandedEditText, expandedInputEditText;
    private TextView outputText, tvWordCount, tvInputEditorWordCount, tvResultStaleWarning;
    private ScrollView scrollView, editorScrollView;
    private ProgressBar progressBar;
    private Button btnCheck, btnCopy, btnSaveTxt, btnPaste, btnClear, btnImport;
    private RadioButton rbFast, rbPro;
    private RadioGroup rgMode;
    private DrawerLayout drawerLayout;
    private SharedPreferences sp;
    private boolean currentIsFast, hasStartedChecking, autoScrollEnabled = true, isTouchingScrollView, isTyposExpanded, isRestoringHistory, isManuallyEditedOut, displayedResultStale, originalIsManuallyEdited, isEditorSelfModifying, firstEditorCursorTapPending, isInputEditorOpen, isInputEditorSelfModifying, showJumpHintForCurrentResult, pendingFreshJumpHintDecision;
    private volatile boolean isCheckingMain, modelsLoading;
    private volatile long inferenceGeneration;
    private int saveFormat;
    private String displayedResultInput, screenStateToken;
    private String pendingSaveText = "", lastSavedHistoryFileId, editingTypoKey, originalEditorText = "", originalInputEditorText = "";
    private SpannableStringBuilder lastEditorSpannable;
    private final Stack<EditorState> editorUndoStack = new Stack<>(), editorRedoStack = new Stack<>();
    private final Stack<InputEdit> inputUndoStack = new Stack<>(), inputRedoStack = new Stack<>();
    private final InputCounts inputCounts = new InputCounts();
    private final Handler inputSyncHandler = new Handler(Looper.getMainLooper());
    private boolean mainSyncDirty, inputEditorSyncDirty, applyingExternalDraft;
    private long historyRestoreGeneration;
    private final Runnable inputEditorSync = () -> {
        if (!inputEditorSyncDirty || expandedInputEditText == null) return;
        DraftSync.publish(sp, expandedInputEditText.getText().toString()); inputEditorSyncDirty = false;
    };
    private void flushInputSync() {
        inputSyncHandler.removeCallbacksAndMessages(null);
        if (sp != null && inputText != null && (mainSyncDirty || inputEditorSyncDirty)) {
            CharSequence text = isInputEditorOpen && expandedInputEditText != null ? expandedInputEditText.getText() : inputText.getText();
            DraftSync.publish(sp, text.toString());
        }
        mainSyncDirty = false; inputEditorSyncDirty = false;
    }
    static final class InputEdit {
        final int start, insertedLength, selectionStart, snapshotLength;
        final CharSequence removed;
        InputEdit(CharSequence text, int start, int count, int inserted, int selection) {
            this.start = start; insertedLength = inserted; selectionStart = selection; snapshotLength = text.length();
            removed = new SpannableString(text.subSequence(start, start + count));
        }
    }
    private void pushInputEdit(Stack<InputEdit> stack, InputEdit edit) {
        stack.push(edit); int totalCharacters = 0;
        for (int i = stack.size() - 1; i >= 0; i--) {
            totalCharacters += stack.get(i).snapshotLength;
            if (stack.size() > 50 || totalCharacters > 2_000_000) stack.remove(0);
        }
    }
    static final class InputCounts {
        int with, without, left, right, removedWith, removedWithout;
        void reset(CharSequence text) { with = countWithPunctuation(text, 0, text.length()); without = countLettersOrDigits(text, 0, text.length()); }
        void before(CharSequence text, int start, int count) {
            left = Math.max(0, start - 1); right = Math.min(text.length(), start + count + 1);
            if (left > 0 && Character.isLowSurrogate(text.charAt(left)) && Character.isHighSurrogate(text.charAt(left - 1))) left--;
            if (right < text.length() && right > 0 && Character.isHighSurrogate(text.charAt(right - 1)) && Character.isLowSurrogate(text.charAt(right))) right++;
            removedWith = countWithPunctuation(text, left, right); removedWithout = countLettersOrDigits(text, left, right);
        }
        void after(CharSequence text, int before, int count) {
            int end = right - before + count;
            with += countWithPunctuation(text, left, end) - removedWith;
            without += countLettersOrDigits(text, left, end) - removedWithout;
        }
    }
    private final List<ClauseLink> currentClauseLinks = new ArrayList<>();
    private View expandedEditorOverlay, inputEditorOverlay;

    private void pushState(Stack<EditorState> stack, EditorState state) {
        stack.push(state);
        int totalCharacters = 0;
        for (int i = stack.size() - 1; i >= 0; i--) {
            totalCharacters += stack.get(i).text.length();
            if (stack.size() > 50 || totalCharacters > 2_000_000) stack.remove(0);
        }
    }

    private void setupSystemBarInsets() {
        View mainContent = findViewById(R.id.mainContentFrame);
        View drawerContent = findViewById(R.id.drawerContent);
        androidx.core.view.OnApplyWindowInsetsListener listener = (view, insets) -> {
            androidx.core.graphics.Insets bars = insets.getInsets(
                    androidx.core.view.WindowInsetsCompat.Type.systemBars() | androidx.core.view.WindowInsetsCompat.Type.displayCutout());
            view.setPadding(bars.left, bars.top, bars.right, bars.bottom);
            return insets;
        };
        if (mainContent != null) { androidx.core.view.ViewCompat.setOnApplyWindowInsetsListener(mainContent, listener); androidx.core.view.ViewCompat.requestApplyInsets(mainContent); }
        if (drawerContent != null) { androidx.core.view.ViewCompat.setOnApplyWindowInsetsListener(drawerContent, listener); androidx.core.view.ViewCompat.requestApplyInsets(drawerContent); }
        boolean night = (getResources().getConfiguration().uiMode & android.content.res.Configuration.UI_MODE_NIGHT_MASK) == android.content.res.Configuration.UI_MODE_NIGHT_YES;
        androidx.core.view.WindowInsetsControllerCompat controller = androidx.core.view.WindowCompat.getInsetsController(getWindow(), getWindow().getDecorView());
        controller.setAppearanceLightStatusBars(!night);
        controller.setAppearanceLightNavigationBars(!night);
    }

    private void updateFontSize(int textOffset, int systemOffset) {
        float inputSize = 15f + textOffset, outputSize = 15.5f + textOffset; int ui = Math.max(-3, Math.min(3, systemOffset));
        if (inputText != null) inputText.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP, inputSize);
        if (outputText != null) outputText.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP, outputSize);
        if (expandedEditText != null) expandedEditText.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP, outputSize);
        if (expandedInputEditText != null) expandedInputEditText.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP, inputSize);
        TextView title = findViewById(R.id.tvTitle); if (title != null) title.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP, 20 + ui);
        if (rbFast != null) rbFast.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP, 14 + ui); if (rbPro != null) rbPro.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP, 14 + ui);
        if (btnCheck != null) btnCheck.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP, 16 + ui);
        for (Button button : new Button[]{btnImport, btnPaste, btnClear, btnCopy, btnSaveTxt}) if (button != null) button.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP, 13 + ui);
        if (tvWordCount != null) tvWordCount.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP, 11 + ui);
        for (int id : new int[]{R.id.btnEditorIndent, R.id.btnEditorUndo, R.id.btnEditorRedo, R.id.btnEditorSave}) { Button button = findViewById(id); if (button != null) button.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP, 13.5f + ui); }
        for (int id : new int[]{R.id.btnInputEditorIndent, R.id.btnInputEditorUndo, R.id.btnInputEditorRedo, R.id.btnInputEditorDone}) { Button button = findViewById(id); if (button != null) button.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP, 13f + ui); }
        if (tvInputEditorWordCount != null) tvInputEditorWordCount.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP, 15 + ui);
        for (EditText field : new EditText[]{editTemp, editThreshDe1, editThreshDe2, editThreshDe3, editThreshZuo, editThreshZuo4}) if (field != null) field.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP, 13 + ui);
        for (int id : new int[]{R.id.labelDe, R.id.labelDi, R.id.labelDe3, R.id.labelZuo, R.id.labelZuo4}) {
            TextView label = findViewById(id); if (label != null) label.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP, 15 + ui);
        }
        TextView tempLabel = findViewById(R.id.labelTemp); if (tempLabel != null) tempLabel.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP, 12.5f + ui);
        // “系统字号”也覆盖阈值提示和抽屉里的固定文字；动态列表在渲染时按保存的偏移量设置。
        for (int id : new int[]{R.id.tvThresholdHint, R.id.tvWhitelistJumpHint}) {
            TextView label = findViewById(id); if (label != null) label.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP, (id == R.id.tvThresholdHint ? 10f : 11f) + ui);
        }
        for (int id : new int[]{R.id.tvCustomTyposTitle, R.id.tvRecentHistoryTitle}) {
            TextView label = findViewById(id); if (label != null) label.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP, 16f + ui);
        }
        for (int id : new int[]{R.id.etOriginal, R.id.etCorrected}) {
            EditText field = findViewById(id); if (field != null) field.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP, 13f + ui);
        }
        for (int id : new int[]{R.id.btnExpandTypos, R.id.btnAddTypo}) {
            Button button = findViewById(id); if (button != null) button.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP, 12f + ui);
        }
        for (int id : new int[]{R.id.btnClearHistory, R.id.tvCustomTyposArrow}) {
            TextView label = findViewById(id); if (label != null) label.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP, 14f + ui);
        }
    }

    private android.graphics.drawable.GradientDrawable solidSkinDrawable(int color, float radiusDp) {
        android.graphics.drawable.GradientDrawable drawable = new android.graphics.drawable.GradientDrawable();
        drawable.setColor(color); drawable.setCornerRadius(radiusDp * getResources().getDisplayMetrics().density); return drawable;
    }

    private android.graphics.drawable.GradientDrawable gradientSkinDrawable(int[] colors) {
        android.graphics.drawable.GradientDrawable drawable = new android.graphics.drawable.GradientDrawable(android.graphics.drawable.GradientDrawable.Orientation.TL_BR, colors);
        drawable.setGradientType(android.graphics.drawable.GradientDrawable.LINEAR_GRADIENT); drawable.setDither(true); return drawable;
    }

    private int skinAccent(String skin) {
        if ("egg".equals(skin)) return Color.parseColor("#E1A62E");
        if ("green".equals(skin)) return Color.parseColor("#58A66A");
        if ("blue".equals(skin)) return Color.parseColor("#63A7D8");
        if ("gradient".equals(skin)) return Color.parseColor("#6C9B84");
        return Color.parseColor("#90A4AE");
    }

    private int blendColor(int from, int to, float ratio) {
        float t = Math.max(0f, Math.min(1f, ratio));
        int a = Math.round(Color.alpha(from) * (1f - t) + Color.alpha(to) * t);
        int r = Math.round(Color.red(from) * (1f - t) + Color.red(to) * t);
        int g = Math.round(Color.green(from) * (1f - t) + Color.green(to) * t);
        int b = Math.round(Color.blue(from) * (1f - t) + Color.blue(to) * t);
        return Color.argb(a, r, g, b);
    }

    private int applyDepthToColor(int color, int depth) {
        if (depth == 0) return color;
        float[] hsv = new float[3];
        Color.colorToHSV(color, hsv);
        float amount = Math.min(1f, Math.abs(depth) / 50f);
        if (depth > 0) {
            hsv[1] = Math.min(1f, hsv[1] + 0.42f * amount);
            hsv[2] = Math.max(0.28f, hsv[2] - 0.10f * amount);
        } else {
            hsv[1] = Math.max(0f, hsv[1] - 0.18f * amount);
            hsv[2] = Math.min(1f, hsv[2] + 0.12f * amount);
        }
        return Color.HSVToColor(Color.alpha(color), hsv);
    }

    private int[][] gradientPresetPalettes() {
        return new int[][]{
                new int[]{Color.parseColor("#FFF4D8"), Color.parseColor("#FFE7CF"), Color.parseColor("#F9E8D9"), Color.parseColor("#F6F2E8")},
                new int[]{Color.parseColor("#EAF7E8"), Color.parseColor("#DDF4E4"), Color.parseColor("#D8F0EC"), Color.parseColor("#EAF6F8")},
                new int[]{Color.parseColor("#EAF2FF"), Color.parseColor("#DCEBFF"), Color.parseColor("#D8F4FF"), Color.parseColor("#E9FBFF")},
                new int[]{Color.parseColor("#FFE9E7"), Color.parseColor("#FFE2EF"), Color.parseColor("#F7E3FF"), Color.parseColor("#EEF0FF")},
                new int[]{Color.parseColor("#FDF0D8"), Color.parseColor("#F8EDCA"), Color.parseColor("#E6F0C9"), Color.parseColor("#D8F0D5"), Color.parseColor("#DDEFFF")},
                new int[]{Color.parseColor("#FFE1C7"), Color.parseColor("#FFCDB8"), Color.parseColor("#FFB8BF"), Color.parseColor("#DDBBFF")},
                new int[]{Color.parseColor("#D9F2FF"), Color.parseColor("#CBE9FF"), Color.parseColor("#C7E1FF"), Color.parseColor("#D7DAFF"), Color.parseColor("#ECE1FF")},
                new int[]{Color.parseColor("#E2F7EF"), Color.parseColor("#D2F5E1"), Color.parseColor("#C6EFDA"), Color.parseColor("#DDF8F1")},
                new int[]{Color.parseColor("#FFF1DF"), Color.parseColor("#FFF6E6"), Color.parseColor("#F2F5E9"), Color.parseColor("#E9F6F0"), Color.parseColor("#E9F1FB")},
                new int[]{Color.parseColor("#FCE6EE"), Color.parseColor("#F6E4F7"), Color.parseColor("#EDE6FF"), Color.parseColor("#E3EEFF")},
                new int[]{Color.parseColor("#FFF2CC"), Color.parseColor("#FBEAB0"), Color.parseColor("#E6F1BA"), Color.parseColor("#CFEFCF"), Color.parseColor("#CFE6FF")},
                new int[]{Color.parseColor("#E7F5FF"), Color.parseColor("#D8F1FF"), Color.parseColor("#D7F7F5"), Color.parseColor("#E7F8E8"), Color.parseColor("#F6F9EA")},
                new int[]{Color.parseColor("#FFE3D5"), Color.parseColor("#FFE9D0"), Color.parseColor("#FFF0DA"), Color.parseColor("#F6F0E8")},
                new int[]{Color.parseColor("#E7ECFF"), Color.parseColor("#DDE7FF"), Color.parseColor("#DDEFFF"), Color.parseColor("#E4F5FF"), Color.parseColor("#EEF8FF")}
        };
    }

    private void randomizeGradientSkinPalette() {
        int[][] presets = gradientPresetPalettes();
        int[] picked = presets[new java.util.Random().nextInt(presets.length)];
        android.content.SharedPreferences.Editor editor = sp.edit();
        editor.putInt("skin_gradient_count", picked.length);
        for (int i = 0; i < 5; i++) {
            if (i < picked.length) editor.putInt("skin_gradient_" + (i + 1), picked[i]);
            else editor.remove("skin_gradient_" + (i + 1));
        }
        editor.apply();
    }

    private int[] getGradientSkinPalette(boolean night) {
        int count = sp.getInt("skin_gradient_count", 0);
        if (count < 4 || !sp.contains("skin_gradient_1") || !sp.contains("skin_gradient_2") || !sp.contains("skin_gradient_3")) {
            randomizeGradientSkinPalette();
            count = sp.getInt("skin_gradient_count", 4);
        }
        count = Math.max(4, Math.min(5, count));
        int[] fallbacks = new int[]{Color.parseColor("#FFF0CF"), Color.parseColor("#E9F7E9"), Color.parseColor("#ECEBFF"), Color.parseColor("#D9F4FF"), Color.parseColor("#FFF7E5")};
        int[] colors = new int[count];
        for (int i = 0; i < count; i++) colors[i] = sp.getInt("skin_gradient_" + (i + 1), fallbacks[i]);
        if (night) for (int i = 0; i < colors.length; i++) colors[i] = blendColor(colors[i], Color.BLACK, 0.78f);
        return colors;
    }

    private void applySkin(String skin) {
        boolean night = (getResources().getConfiguration().uiMode & android.content.res.Configuration.UI_MODE_NIGHT_MASK) == android.content.res.Configuration.UI_MODE_NIGHT_YES;
        int bg, card;
        int[] gradient = null;
        if ("egg".equals(skin)) { bg = Color.parseColor(night ? "#292417" : "#FFF3C9"); card = Color.parseColor(night ? "#342D1B" : "#FFF9E6"); }
        else if ("green".equals(skin)) { bg = Color.parseColor(night ? "#17271B" : "#E6F5E7"); card = Color.parseColor(night ? "#203423" : "#F5FFF4"); }
        else if ("blue".equals(skin)) { bg = Color.parseColor(night ? "#17232D" : "#E8F4FB"); card = Color.parseColor(night ? "#1F303C" : "#F5FBFF"); }
        else if ("gradient".equals(skin)) { bg = Color.parseColor(night ? "#23242C" : "#F7F1E8"); card = Color.parseColor(night ? "#2B2D36" : "#FFFDF8"); gradient = getGradientSkinPalette(night); }
        else { bg = androidx.core.content.ContextCompat.getColor(this, R.color.bg_color); card = androidx.core.content.ContextCompat.getColor(this, R.color.card_bg); }
        int depth = "default".equals(skin) ? 0 : sp.getInt("skin_depth", 50) - 50;
        bg = applyDepthToColor(bg, depth); card = applyDepthToColor(card, depth);
        if (gradient != null) for (int i = 0; i < gradient.length; i++) gradient[i] = applyDepthToColor(gradient[i], depth);

        View mainContentFrame = findViewById(R.id.mainContentFrame), mainBody = findViewById(R.id.mainBody), drawerContent = findViewById(R.id.drawerContent), inputOverlay = findViewById(R.id.inputEditorOverlay), expandedOverlay = findViewById(R.id.expandedEditorOverlay);
        if (gradient != null) {
            if (drawerLayout != null) drawerLayout.setBackground(gradientSkinDrawable(gradient.clone()));
            if (mainContentFrame != null) mainContentFrame.setBackgroundColor(Color.TRANSPARENT);
            if (mainBody != null) mainBody.setBackgroundColor(Color.TRANSPARENT);
            if (drawerContent != null) drawerContent.setBackground(gradientSkinDrawable(gradient.clone()));
            if (inputOverlay != null) inputOverlay.setBackground(gradientSkinDrawable(gradient.clone()));
            if (expandedOverlay != null) expandedOverlay.setBackground(gradientSkinDrawable(gradient.clone()));
        } else {
            if (drawerLayout != null) drawerLayout.setBackground(solidSkinDrawable(bg, 0));
            if (mainContentFrame != null) mainContentFrame.setBackgroundColor(Color.TRANSPARENT);
            if (mainBody != null) mainBody.setBackgroundColor(Color.TRANSPARENT);
            for (int id : new int[]{R.id.drawerContent, R.id.inputEditorOverlay, R.id.expandedEditorOverlay}) { View view = findViewById(id); if (view != null) view.setBackground(solidSkinDrawable(bg, 0)); }
        }
        int[] cardIds = new int[]{R.id.paramsCard, R.id.inputText, R.id.outputText, R.id.inputEditorToolbar, R.id.outputEditorToolbar};
        int[] cardGradient = gradient == null ? null : gradient.clone();
        if (cardGradient != null) for (int i = 0; i < cardGradient.length; i++) cardGradient[i] = blendColor(cardGradient[i], Color.WHITE, night ? .06f : .22f);
        for (int id : cardIds) {
            View view = findViewById(id); if (view == null) continue;
            float radius = (id == R.id.inputText || id == R.id.outputText || id == R.id.paramsCard) ? 8 : 0;
            android.graphics.drawable.GradientDrawable drawable = cardGradient == null ? solidSkinDrawable(card, radius) : gradientSkinDrawable(cardGradient.clone());
            if (cardGradient != null) drawable.setCornerRadius(radius * getResources().getDisplayMetrics().density);
            view.setBackground(drawable);
        }

        androidx.core.view.WindowInsetsControllerCompat controller = androidx.core.view.WindowCompat.getInsetsController(getWindow(), getWindow().getDecorView());
        boolean lightBars = !night || !"default".equals(skin);
        controller.setAppearanceLightStatusBars(lightBars); controller.setAppearanceLightNavigationBars(lightBars);
        if (android.os.Build.VERSION.SDK_INT < 35) {
            if (gradient != null) {
                getWindow().setStatusBarColor(Color.TRANSPARENT);
                getWindow().setNavigationBarColor(Color.TRANSPARENT);
            } else {
                getWindow().setStatusBarColor(bg);
                getWindow().setNavigationBarColor(bg);
            }
        }
    }

    private void showFontSizeDialog() {
        int textOffset = sp.getInt("font_offset_text", 0), systemOffset = sp.getInt("font_offset_sys", 0), skinDepth = sp.getInt("skin_depth", 50);
        float density = getResources().getDisplayMetrics().density;
        LinearLayout layout = new LinearLayout(this); layout.setOrientation(LinearLayout.VERTICAL); layout.setPadding((int) (24 * density), (int) (20 * density), (int) (24 * density), (int) (12 * density));
        TextView title = new TextView(this); title.setText("调节字体大小"); title.setTextSize(18f); title.setTextColor(Color.BLACK); title.setTypeface(android.graphics.Typeface.create("sans-serif-medium", 0));
        TextView textLabel = new TextView(this); textLabel.setText("正文字号 (输入/输出/便签): " + (15 + textOffset)); textLabel.setTextSize(14f); textLabel.setTextColor(0xFF666666); textLabel.setPadding(0, (int) (18 * density), 0, (int) (4 * density));
        android.widget.SeekBar textSeek = new android.widget.SeekBar(this); textSeek.setMax(14); textSeek.setProgress(textOffset + 4); textSeek.setPadding((int) (8 * density), 0, (int) (8 * density), (int) (10 * density));
        TextView systemLabel = new TextView(this); systemLabel.setText("系统字号 (按钮/标题等): " + (systemOffset > 0 ? "+" + systemOffset : systemOffset)); systemLabel.setTextSize(14f); systemLabel.setTextColor(0xFF666666); systemLabel.setPadding(0, (int) (6 * density), 0, (int) (4 * density));
        android.widget.SeekBar systemSeek = new android.widget.SeekBar(this); systemSeek.setMax(6); systemSeek.setProgress(Math.max(0, Math.min(6, systemOffset + 3))); systemSeek.setPadding((int) (8 * density), 0, (int) (8 * density), (int) (10 * density));

        LinearLayout skinRow = new LinearLayout(this); skinRow.setOrientation(LinearLayout.HORIZONTAL); skinRow.setGravity(android.view.Gravity.CENTER); skinRow.setPadding(0, (int) (6 * density), 0, (int) (2 * density));
        TextView depthLabel = new TextView(this); depthLabel.setText("界面深浅"); depthLabel.setTextSize(13f); depthLabel.setTextColor(0xFF777777); depthLabel.setPadding(0, (int) (8 * density), 0, 0);
        android.widget.SeekBar depthSeek = new android.widget.SeekBar(this); depthSeek.setMax(100); depthSeek.setProgress(skinDepth); depthSeek.setPadding((int) (8 * density), 0, (int) (8 * density), (int) (6 * density));
        Runnable refreshDepthVisibility = () -> {
            boolean showDepth = !"default".equals(sp.getString("ui_skin", "default"));
            depthLabel.setVisibility(showDepth ? View.VISIBLE : View.GONE);
            depthSeek.setVisibility(showDepth ? View.VISIBLE : View.GONE);
        };
        final String[] skinKeys = new String[]{"default", "egg", "green", "blue", "gradient"};
        final android.widget.ImageButton[] skinButtons = new android.widget.ImageButton[skinKeys.length];
        Runnable refreshSkinSelection = () -> {
            String selected = sp.getString("ui_skin", "default");
            for (int i = 0; i < skinButtons.length; i++) {
                android.widget.ImageButton button = skinButtons[i]; if (button == null) continue;
                boolean active = skinKeys[i].equals(selected);
                android.graphics.drawable.GradientDrawable bg = new android.graphics.drawable.GradientDrawable(); bg.setShape(android.graphics.drawable.GradientDrawable.OVAL);
                bg.setColor(active ? 0x143F51B5 : Color.TRANSPARENT); bg.setStroke((int) ((active ? 2 : 1) * density), active ? skinAccent(skinKeys[i]) : 0x22000000); button.setBackground(bg);
            }
        };
        for (int i = 0; i < skinKeys.length; i++) {
            final String key = skinKeys[i];
            android.widget.ImageButton choice = new android.widget.ImageButton(this); skinButtons[i] = choice;
            choice.setImageResource("gradient".equals(key) ? R.drawable.ic_skin_shirt_gradient : R.drawable.ic_skin_shirt);
            if (!"gradient".equals(key)) choice.setColorFilter(skinAccent(key)); else choice.clearColorFilter();
            choice.setScaleType(android.widget.ImageView.ScaleType.FIT_CENTER); choice.setPadding((int) (5 * density), (int) (8 * density), (int) (5 * density), (int) (8 * density)); choice.setContentDescription("界面皮肤");
            LinearLayout.LayoutParams choiceParams = new LinearLayout.LayoutParams((int) (39 * density), (int) (39 * density)); choiceParams.setMargins((int) (3 * density), 0, (int) (3 * density), 0); skinRow.addView(choice, choiceParams);
            choice.setOnClickListener(v -> { if ("gradient".equals(key)) randomizeGradientSkinPalette(); sp.edit().putString("ui_skin", key).apply(); applySkin(key); refreshSkinSelection.run(); refreshDepthVisibility.run(); });
        }
        refreshSkinSelection.run();
        depthSeek.setOnSeekBarChangeListener(new SimpleSeekListener() {
            @Override public void onProgressChanged(android.widget.SeekBar seekBar, int progress, boolean fromUser) {
                sp.edit().putInt("skin_depth", progress).apply();
                applySkin(sp.getString("ui_skin", "default"));
            }
        });

        Button done = new Button(this); done.setText("完成"); done.setTextColor(0xFF2196F3); done.setBackgroundColor(Color.TRANSPARENT); LinearLayout.LayoutParams doneParams = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT); doneParams.gravity = android.view.Gravity.END; doneParams.rightMargin = (int) (1 * density); done.setLayoutParams(doneParams);
        Button reset = new Button(this); reset.setText("恢复默认"); reset.setTextColor(0xFF777777); reset.setBackgroundColor(Color.TRANSPARENT);
        LinearLayout actions = new LinearLayout(this); actions.setOrientation(LinearLayout.HORIZONTAL); actions.setGravity(android.view.Gravity.END | android.view.Gravity.CENTER_VERTICAL); actions.addView(reset); actions.addView(done);
        // 将按钮文字向字号滑条右端对齐，不改变弹窗内容的横向留白。
        actions.setTranslationX(24f * density);
        // 弹窗本身同样跟随“系统字号”；按钮保留系统主题的原始字号作为 0 档基准。
        float resetBaseSp = reset.getTextSize() / getResources().getDisplayMetrics().scaledDensity;
        float doneBaseSp = done.getTextSize() / getResources().getDisplayMetrics().scaledDensity;
        Runnable refreshDialogTextSizes = () -> {
            int ui = systemSeek.getProgress() - 3;
            title.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP, 18f + ui);
            textLabel.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP, 14f + ui);
            systemLabel.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP, 14f + ui);
            depthLabel.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP, 13f + ui);
            reset.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP, resetBaseSp + ui);
            done.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP, doneBaseSp + ui);
        };
        refreshDialogTextSizes.run();
        textSeek.setOnSeekBarChangeListener(new SimpleSeekListener() { @Override public void onProgressChanged(android.widget.SeekBar seekBar, int progress, boolean fromUser) { int offset = progress - 4; textLabel.setText("正文字号 (输入/输出/便签): " + (15 + offset)); updateFontSize(offset, systemSeek.getProgress() - 3); } });
        systemSeek.setOnSeekBarChangeListener(new SimpleSeekListener() { @Override public void onProgressChanged(android.widget.SeekBar seekBar, int progress, boolean fromUser) { int offset = progress - 3; systemLabel.setText("系统字号 (按钮/标题等): " + (offset > 0 ? "+" + offset : offset)); refreshDialogTextSizes.run(); updateFontSize(textSeek.getProgress() - 4, offset); } });
        layout.addView(title); layout.addView(textLabel); layout.addView(textSeek); layout.addView(systemLabel); layout.addView(systemSeek); layout.addView(skinRow); layout.addView(depthLabel); layout.addView(depthSeek); layout.addView(actions); refreshDepthVisibility.run();
        android.app.AlertDialog dialog = new android.app.AlertDialog.Builder(this).setView(layout).create();
        Runnable persist = () -> sp.edit().putInt("font_offset_text", textSeek.getProgress() - 4).putInt("font_offset_sys", systemSeek.getProgress() - 3).putInt("skin_depth", depthSeek.getProgress()).apply();
        reset.setOnClickListener(v -> {
            android.content.SharedPreferences.Editor editor = sp.edit().putInt("font_offset_text", 0).putInt("font_offset_sys", 0).putString("ui_skin", "default").putInt("skin_depth", 50).remove("skin_gradient_count");
            for (int i = 1; i <= 5; i++) editor.remove("skin_gradient_" + i);
            editor.apply();
            textSeek.setProgress(4); systemSeek.setProgress(3); depthSeek.setProgress(50);
            textLabel.setText("正文字号 (输入/输出/便签): 15"); systemLabel.setText("系统字号 (按钮/标题等): 0");
            updateFontSize(0, 0); applySkin("default"); refreshSkinSelection.run(); refreshDepthVisibility.run();
        });
        done.setOnClickListener(v -> { persist.run(); dialog.dismiss(); }); dialog.setOnCancelListener(d -> persist.run()); dialog.show();
        WindowManager.LayoutParams params = new WindowManager.LayoutParams(); params.copyFrom(dialog.getWindow().getAttributes()); params.dimAmount = Math.max(0f, Math.min(1f, params.dimAmount * .9f)); params.width = (int) (getResources().getDisplayMetrics().widthPixels * 0.86f); params.gravity = android.view.Gravity.TOP | android.view.Gravity.CENTER_HORIZONTAL; params.y = (int) (getResources().getDisplayMetrics().heightPixels * 0.12f); dialog.getWindow().setAttributes(params);
        android.graphics.drawable.GradientDrawable background = new android.graphics.drawable.GradientDrawable(); background.setColor(Color.WHITE); background.setCornerRadius(16f); dialog.getWindow().setBackgroundDrawable(background);
    }

    private abstract static class SimpleSeekListener implements android.widget.SeekBar.OnSeekBarChangeListener {
        @Override public void onStartTrackingTouch(android.widget.SeekBar seekBar) {}
        @Override public void onStopTrackingTouch(android.widget.SeekBar seekBar) {}
    }

    private void loadSettings(boolean fast) {
        if (!sp.getBoolean("hcam_params_v1", false)) {
            String oldT = sp.getString("pro_temp", null);
            String oldDe = sp.getString("pro_th1", null);
            String oldDi = sp.getString("pro_th2", null);
            String oldDe3 = sp.getString("pro_th3", null);
            boolean unset = oldT == null && oldDe == null && oldDi == null && oldDe3 == null;
            boolean oldDefaultA = "1.2".equals(oldT) && "0.76".equals(oldDe) && "0.74".equals(oldDi) && "0.78".equals(oldDe3);
            boolean oldDefaultB = "1.1".equals(oldT) && "0.76".equals(oldDe) && "0.72".equals(oldDi) && "0.74".equals(oldDe3);
            boolean interimDilaGloDefault = "0.8".equals(oldT) && "0.72".equals(oldDe) && "0.68".equals(oldDi) && "0.74".equals(oldDe3);
            boolean previousDilaGloFinal = "0.8".equals(oldT) && "0.72".equals(oldDe) && "0.72".equals(oldDi) && "0.80".equals(oldDe3);
            SharedPreferences.Editor migration = sp.edit().putBoolean("hcam_params_v1", true);
            if (unset || oldDefaultA || oldDefaultB || interimDilaGloDefault || previousDilaGloFinal) {
                migration.putString("pro_temp", "1.0").putString("pro_th1", "0.68").putString("pro_th2", "0.68").putString("pro_th3", "0.72");
            }
            migration.apply();
        }
        if(!sp.getBoolean("hcam_v2_five",false)) {
            SharedPreferences.Editor migration=sp.edit().putBoolean("hcam_v2_five",true);
            if("1.0".equals(sp.getString("pro_temp","1.0"))&&"0.68".equals(sp.getString("pro_th1","0.68"))&&"0.68".equals(sp.getString("pro_th2","0.68"))&&"0.72".equals(sp.getString("pro_th3","0.72")))migration.putString("pro_th3","0.74");
            migration.apply();
        }
        if(!sp.getBoolean("hcam_thresholds_20261011",false)) {
            SharedPreferences.Editor defaults=sp.edit().putBoolean("hcam_thresholds_20261011",true);
            String[] keys={"pro_th1","pro_th2","pro_th3","pro_th4","pro_th5"};
            for(int i=0;i<keys.length;i++) {
                String old=i<2?"0.68":"0.74", next=i<2?"0.7":"0.75";
                if(old.equals(sp.getString(keys[i],old))) defaults.putString(keys[i],next);
            }
            defaults.apply();
        }
        String temperature = sp.getString("pro_temp", "1.0");
        if (!isTemperatureValid(parseFloatSafe(temperature, Float.NaN))) {
            temperature = "1.0";
            sp.edit().putString("pro_temp", temperature).apply();
            Toast.makeText(this, "温度参数无效，已自动恢复为1.0（允许范围0.5～2.0）", Toast.LENGTH_LONG).show();
        }
        // 两种模式显示同一组专业参数；极速模式只禁用并置灰，不再换成另一套数字。
        editTemp.setText(temperature);
        editThreshDe1.setText(sp.getString("pro_th1", "0.7"));
        editThreshDe2.setText(sp.getString("pro_th2", "0.7"));
        editThreshDe3.setText(sp.getString("pro_th3", "0.75"));
        editThreshZuo.setText(sp.getString("pro_th4", "0.75")); editThreshZuo4.setText(sp.getString("pro_th5", "0.75"));
        boolean professional = !fast;
        for (EditText field : new EditText[]{editTemp, editThreshDe1, editThreshDe2, editThreshDe3, editThreshZuo, editThreshZuo4}) {
            field.setEnabled(professional);
            field.setAlpha(professional ? 1f : 0.45f);
        }
    }

    private void saveSettings(boolean fast) {
        if (fast) return;
        SharedPreferences.Editor editor = sp.edit()
                .putString("pro_th1", editThreshDe1.getText().toString())
                .putString("pro_th2", editThreshDe2.getText().toString())
                .putString("pro_th3", editThreshDe3.getText().toString())
                .putString("pro_th4", editThreshZuo.getText().toString()).putString("pro_th5", editThreshZuo4.getText().toString());
        float temperature = parseFloatSafe(editTemp.getText().toString(), Float.NaN);
        if (isTemperatureValid(temperature)) editor.putString("pro_temp", editTemp.getText().toString());
        editor.apply();
    }

    private void saveHistory(String text, String fileId) {
        HistoryStore.save(this, sp, text, fileId, savedId -> {
            if (!isFinishing() && !isDestroyed() && inputText != null && text.equals(inputText.getText().toString())) lastSavedHistoryFileId = savedId;
            renderHistoryUI();
        });
    }

    private void openFilePicker() {
        Intent intent = new Intent(Intent.ACTION_GET_CONTENT); intent.setType("*/*"); intent.putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true); intent.putExtra(Intent.EXTRA_MIME_TYPES, new String[]{"text/plain", "text/markdown", "application/vnd.openxmlformats-officedocument.wordprocessingml.document", "application/vnd.openxmlformats-officedocument.presentationml.presentation", "application/pdf", "image/*"}); startActivityForResult(intent, 102);
    }

    private void startFloatingService() {
        flushInputSync();
        Intent intent = new Intent(this, FloatingService.class);
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) startForegroundService(intent); else startService(intent);
        Toast.makeText(this, "悬浮窗已开启", Toast.LENGTH_SHORT).show(); moveTaskToBack(true);
    }

    private static void loadCharVocab(Context context, String asset) throws Exception {
        String json=SecureAsset.readUtf8(context,asset);
        if(json==null||json.isEmpty())throw new IllegalStateException("词表解密失败："+SecureAsset.lastErrorSummary());
        proTokenizer=new HcamTokenizer(json);proVocabReady=true;
    }

    private static File createRuntimePlainModelFile(Context context, String cacheKey) throws IOException {
        File directory = new File(context.getCacheDir(), "dedede_runtime_models");
        if (!directory.exists() && !directory.mkdirs()) throw new IOException("无法创建临时模型目录");
        File[] stale = directory.listFiles((dir, name) -> (name.endsWith(".pte") || name.endsWith(".onnx")));
        if (stale != null) for (File file : stale) if (!file.equals(proPlainModelFile) && !file.delete()) file.deleteOnExit();
        String safe = cacheKey.replaceAll("[^a-zA-Z0-9._-]", "_");
        return new File(directory, "runtime_" + safe + "_" + System.nanoTime() + ModelEngine.EXT);
    }

    private static ModelEngine loadDecryptedModule(Context context, String assetName, String cacheKey, Object modelLock) throws Exception {
        synchronized (modelLock) {
            File plainModel = createRuntimePlainModelFile(context, cacheKey);
            long decryptStart = System.currentTimeMillis();
            if (!SecureAsset.decryptToFile(context, assetName, plainModel)) {
                plainModel.delete();
                throw new Exception("模型完整性校验或解密失败：" + SecureAsset.lastErrorSummary());
            }
            if (!plainModel.isFile() || plainModel.length() <= 4096L) {
                plainModel.delete();
                throw new IOException("生成的临时模型文件异常");
            }
            android.util.Log.i("DededeModel", "模型临时解密完成：" + assetName + "，耗时 " + (System.currentTimeMillis() - decryptStart) + "ms");
            try {
                long loadStart = System.currentTimeMillis();
                ModelEngine module = ModelEngine.load(plainModel.getAbsolutePath());
                proPlainModelFile = plainModel;
                android.util.Log.i("DededeModel", "HCAM 模型载入完成，耗时 " + (System.currentTimeMillis() - loadStart) + "ms");
                return module;
            } catch (Throwable error) {
                plainModel.delete();
                if (error instanceof Exception) throw (Exception) error;
                if (error instanceof Error) throw (Error) error;
                throw new Exception("模型加载失败", error);
            }
        }
    }

    @SuppressLint("ClickableViewAccessibility")
    @Override protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        androidx.core.view.WindowCompat.setDecorFitsSystemWindows(getWindow(), false);
        setContentView(R.layout.activity_main);
        setupSystemBarInsets();
        instance = this; sp = getSharedPreferences("DededeConfig", MODE_PRIVATE);
        Intent launchIntent = getIntent();
        boolean firstActivityInProcess = !processSessionInitialized;
        processSessionInitialized = true;
        boolean carriesExternalText = launchIntent != null && (launchIntent.hasExtra("SYNC_TEXT")
                || (Intent.ACTION_SEND.equals(launchIntent.getAction()) && launchIntent.getType() != null));
        // sync_text 只负责同一进程内主界面与悬浮窗同步，不作为跨进程“草稿恢复”。
        // 系统后台回收后重建必须保留草稿；真正结束任务再从桌面冷启动仍保持原来的清空行为。
        if (firstActivityInProcess && savedInstanceState == null && !carriesExternalText) DraftSync.publish(sp, "");
        drawerLayout = findViewById(R.id.drawerLayout); inputText = findViewById(R.id.inputText); outputText = findViewById(R.id.outputText); tvWordCount = findViewById(R.id.tvWordCount); tvResultStaleWarning = findViewById(R.id.tvResultStaleWarning); scrollView = findViewById(R.id.scrollView); progressBar = findViewById(R.id.progressBar);
        editTemp = findViewById(R.id.editTemp); editThreshDe1 = findViewById(R.id.editThreshDe1); editThreshDe2 = findViewById(R.id.editThreshDe2); editThreshDe3 = findViewById(R.id.editThreshDe3); editThreshZuo=findViewById(R.id.editThreshZuo); editThreshZuo4=findViewById(R.id.editThreshZuo4);
        btnCheck = findViewById(R.id.btnCheck); btnImport = findViewById(R.id.btnImport); btnPaste = findViewById(R.id.btnPaste); btnClear = findViewById(R.id.btnClear); btnCopy = findViewById(R.id.btnCopy); btnSaveTxt = findViewById(R.id.btnSaveTxt);
        rbFast = findViewById(R.id.rbFast); rbPro = findViewById(R.id.rbPro); rgMode = findViewById(R.id.rgMode); expandedEditorOverlay = findViewById(R.id.expandedEditorOverlay); expandedEditText = findViewById(R.id.expandedEditText); editorScrollView = findViewById(R.id.editorScrollView);
        inputEditorOverlay = findViewById(R.id.inputEditorOverlay); expandedInputEditText = findViewById(R.id.expandedInputEditText); tvInputEditorWordCount = findViewById(R.id.tvInputEditorWordCount);
        TextView title = findViewById(R.id.tvTitle); Button menu = findViewById(R.id.btnMenu), font = findViewById(R.id.btnFont), inputExpand = findViewById(R.id.btnInputExpand); View floatButton = findViewById(R.id.btnFloat);
        font.setOnClickListener(v -> showFontSizeDialog()); inputExpand.setOnClickListener(v -> openInputEditor()); updateFontSize(sp.getInt("font_offset_text", 0), sp.getInt("font_offset_sys", 0)); applySkin(sp.getString("ui_skin", "default"));
        setupScrollControls(); setupEditor(); setupInputEditor(); setupInputWatcher();
        currentIsFast = sp.getBoolean("is_fast_mode", false); rbFast.setChecked(currentIsFast); rbPro.setChecked(!currentIsFast); loadSettings(currentIsFast);
        rgMode.setOnCheckedChangeListener((group, checkedId) -> {
            if (checkedId == -1) return;
            saveSettings(currentIsFast);
            currentIsFast = checkedId == R.id.rbFast;
            sp.edit().putBoolean("is_fast_mode", currentIsFast).apply();
            loadSettings(currentIsFast);
            if (!currentIsFast && inputText.length() > 0) warmProEngineAsync(this);
        });
        if (savedInstanceState == null) restoreScreenState(null); else restoreScreenState(savedInstanceState);
        if (savedInstanceState == null) handleIntent(getIntent());
        title.setOnClickListener(v -> showHelp());
        menu.setOnClickListener(v -> { editingTypoKey = null; ((Button) findViewById(R.id.btnAddTypo)).setText("添加"); EditText original = findViewById(R.id.etOriginal); original.setText(""); original.setHint("原始文本"); ((EditText) findViewById(R.id.etCorrected)).setText(""); TextView whitelistHint = findViewById(R.id.tvWhitelistJumpHint); if (whitelistHint != null) whitelistHint.setVisibility(View.GONE); drawerLayout.openDrawer(GravityCompat.END); renderCustomTyposUI(); renderHistoryUI(); });
        floatButton.setOnClickListener(v -> {
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M && !android.provider.Settings.canDrawOverlays(this)) startActivityForResult(new Intent(android.provider.Settings.ACTION_MANAGE_OVERLAY_PERMISSION, android.net.Uri.parse("package:" + getPackageName())), 201); else startFloatingService();
        });
        setupMainButtons(); setupDrawerButtons(); btnSaveTxt.setEnabled(inputText.length() > 0 || hasDisplayedCorrectionResult());
        for (TextView editor : new TextView[]{inputText, outputText, expandedInputEditText, expandedEditText, editTemp, editThreshDe1, editThreshDe2, editThreshDe3, editThreshZuo, editThreshZuo4}) editor.setSaveEnabled(false);
    }

    @SuppressLint("ClickableViewAccessibility")
    private void setupScrollControls() {
        View touchArea = findViewById(R.id.scrollTouchArea);
        touchArea.setOnTouchListener((v, event) -> {
            View child = scrollView.getChildAt(0); int max = child == null ? 0 : child.getHeight() - scrollView.getHeight();
            if (max > 0 && v.getHeight() > 0) scrollView.scrollTo(0, (int) (Math.max(0, Math.min(event.getY(), v.getHeight())) / v.getHeight() * max));
            int action = event.getActionMasked(); if (action == MotionEvent.ACTION_DOWN) { isTouchingScrollView = true; autoScrollEnabled = false; } else if (action == MotionEvent.ACTION_UP || action == MotionEvent.ACTION_CANCEL) { isTouchingScrollView = false; if (!scrollView.canScrollVertically(1)) autoScrollEnabled = true; }
            return true;
        });
        scrollView.setOnTouchListener((v, event) -> { int action = event.getActionMasked(); if (action == MotionEvent.ACTION_DOWN) { isTouchingScrollView = true; autoScrollEnabled = false; } else if (action == MotionEvent.ACTION_UP || action == MotionEvent.ACTION_CANCEL) { isTouchingScrollView = false; if (!scrollView.canScrollVertically(1)) autoScrollEnabled = true; } return false; });
        scrollView.setOnScrollChangeListener((v, x, y, oldX, oldY) -> { if (y < oldY) autoScrollEnabled = false; if (!isTouchingScrollView && !v.canScrollVertically(1)) autoScrollEnabled = true; });
        View editorTouch = findViewById(R.id.editorScrollTouchArea);
        editorTouch.setOnTouchListener((v, event) -> { View child = editorScrollView.getChildAt(0); int max = child == null ? 0 : child.getHeight() - editorScrollView.getHeight(); if (max > 0 && v.getHeight() > 0) editorScrollView.scrollTo(0, (int) (Math.max(0, Math.min(event.getY(), v.getHeight())) / v.getHeight() * max)); return true; });
    }

    @SuppressLint("ClickableViewAccessibility")
    private void setupEditor() {
        Button collapse = findViewById(R.id.btnEditorCollapse), indent = findViewById(R.id.btnEditorIndent), save = findViewById(R.id.btnEditorSave), close = findViewById(R.id.btnEditorClose), undo = findViewById(R.id.btnEditorUndo), redo = findViewById(R.id.btnEditorRedo);
        expandedEditText.setOnTouchListener(new View.OnTouchListener() {
            int scrollBeforeTouch;
            boolean protectInitialCursorTap;
            JumpSpan pressedJumpSpan;

            private JumpSpan findJumpSpan(EditText widget, MotionEvent event) {
                Layout layout = widget.getLayout();
                if (layout == null) return null;
                int x = (int) event.getX() - widget.getTotalPaddingLeft() + widget.getScrollX();
                int y = (int) event.getY() - widget.getTotalPaddingTop() + widget.getScrollY();
                if (y < 0 || y > layout.getHeight()) return null;
                int line = layout.getLineForVertical(y);
                if (x < layout.getLineLeft(line) || x > layout.getLineRight(line)) return null;
                int offset = layout.getOffsetForHorizontal(line, x);
                JumpSpan[] links = widget.getText().getSpans(offset, offset, JumpSpan.class);
                return links.length > 0 ? links[0] : null;
            }

            @Override public boolean onTouch(View v, MotionEvent event) {
                EditText widget = (EditText) v;
                int action = event.getActionMasked();
                if (action == MotionEvent.ACTION_DOWN) {
                    scrollBeforeTouch = editorScrollView.getScrollY();
                    protectInitialCursorTap = firstEditorCursorTapPending || !widget.hasFocus();
                    pressedJumpSpan = findJumpSpan(widget, event);
                    // 从按下开始就拦截序号，避免 EditText 把光标/选区放到序号上，随后又自动滚回顶部。
                    return pressedJumpSpan != null;
                }
                if (pressedJumpSpan != null) {
                    if (action == MotionEvent.ACTION_UP) {
                        JumpSpan span = pressedJumpSpan;
                        pressedJumpSpan = null;
                        span.onClick(widget);
                        return true;
                    }
                    if (action == MotionEvent.ACTION_CANCEL) pressedJumpSpan = null;
                    return true;
                }
                if (action != MotionEvent.ACTION_UP) return false;
                Layout layout = widget.getLayout();
                if (layout == null) return false;
                int x = (int) event.getX() - widget.getTotalPaddingLeft() + widget.getScrollX();
                int y = (int) event.getY() - widget.getTotalPaddingTop() + widget.getScrollY();
                int line = layout.getLineForVertical(y);
                int offset = layout.getOffsetForHorizontal(line, x);
                int lockedEnd = 0; for (IgnoredInCopySpan span : widget.getText().getSpans(0, widget.length(), IgnoredInCopySpan.class)) lockedEnd = Math.max(lockedEnd, widget.getText().getSpanEnd(span));
                if (offset < lockedEnd) { int end = lockedEnd; widget.post(() -> widget.setSelection(Math.min(end, widget.length()))); }
                boolean extendedProtection = protectInitialCursorTap;
                firstEditorCursorTapPending = false;
                stabilizeEditorScrollAfterTap(scrollBeforeTouch, extendedProtection);
                return false;
            }
        });
        expandedEditText.addTextChangedListener(new TextWatcher() {
            @Override public void beforeTextChanged(CharSequence s, int start, int count, int after) {
                if (isEditorSelfModifying || isCheckingMain || currentClauseLinks == null) return;
                pushState(editorUndoStack, new EditorState(new SpannableStringBuilder(s), expandedEditText.getSelectionStart())); editorRedoStack.clear();
            }
            @Override public void onTextChanged(CharSequence s, int start, int before, int count) {}
            @Override public void afterTextChanged(Editable editable) {
                if (isCheckingMain || isEditorSelfModifying) return; boolean purge = false;
                for (ClauseLink link : currentClauseLinks) {
                    if (link.isDead) continue; boolean altered = false;
                    for (TargetSpan target : link.targetSpans) {
                        int start = editable.getSpanStart(target), end = editable.getSpanEnd(target);
                        if (start < 0 || end < 0 || !editable.subSequence(start, end).toString().equals(target.expected)) { altered = true; break; }
                    }
                    if (altered) { link.isDead = true; purge = true; }
                }
                if (purge) expandedEditText.post(() -> purgeDeadClauseMarkers(expandedEditText.getText()));
            }
        });
        expandedEditText.setFilters(new InputFilter[]{(source, start, end, dest, dstart, dend) -> {
            if (isEditorSelfModifying) return null; Editable editable = expandedEditText.getText(); if (editable == null) return null;
            for (IgnoredInCopySpan span : editable.getSpans(Math.max(0, dstart - 1), Math.min(editable.length(), dend + 1), IgnoredInCopySpan.class)) {
                int spanStart = editable.getSpanStart(span), spanEnd = editable.getSpanEnd(span);
                if (Math.max(dstart, spanStart) < Math.min(dend, spanEnd) || (dstart > spanStart && dstart < spanEnd)) return dest.subSequence(dstart, dend);
            }
            return null;
        }});
        setupOutputLongPress();
        Runnable apply = () -> applyEditorChanges();
        collapse.setOnClickListener(v -> apply.run());
        close.setOnClickListener(v -> {
            if (!expandedEditText.getText().toString().equals(originalEditorText)) new AlertDialog.Builder(this).setMessage("保留此次更改吗？").setPositiveButton("是", (d, w) -> apply.run()).setNegativeButton("否", (d, w) -> closeEditor()).show(); else closeEditor();
        });
        indent.setOnClickListener(v -> applyIndent());
        undo.setOnClickListener(v -> restoreEditorState(editorUndoStack, editorRedoStack, true));
        redo.setOnClickListener(v -> { if (editorRedoStack.isEmpty()) Toast.makeText(this, "上一步非撤销操作，无法还原", Toast.LENGTH_SHORT).show(); else restoreEditorState(editorRedoStack, editorUndoStack, false); });
        save.setOnClickListener(v -> { isManuallyEditedOut = true; outputText.setText(expandedEditText.getText()); btnSaveTxt.performClick(); });
    }

    private void stabilizeEditorScrollAfterTap(int expectedScrollY, boolean extendedProtection) {
        if (editorScrollView == null) return;
        Runnable restoreIfJumped = () -> {
            if (!isEditorOpen || editorScrollView == null) return;
            View child = editorScrollView.getChildAt(0);
            int maxScrollY = child == null ? 0 : Math.max(0, child.getHeight() - editorScrollView.getHeight());
            int targetScrollY = Math.max(0, Math.min(expectedScrollY, maxScrollY));
            int currentScrollY = editorScrollView.getScrollY();
            int threshold = Math.max(96, Math.max((int) (48f * getResources().getDisplayMetrics().density), editorScrollView.getHeight() / 6));
            // 只修复系统首次聚焦/键盘重排造成的“掉到顶部附近”，不干预正常的小幅自动调整或手动滚动。
            if (targetScrollY > threshold * 2 && currentScrollY <= threshold * 2 && targetScrollY - currentScrollY > threshold * 2) {
                editorScrollView.scrollTo(0, targetScrollY);
            }
        };
        editorScrollView.post(restoreIfJumped);
        editorScrollView.postDelayed(restoreIfJumped, 48);
        editorScrollView.postDelayed(restoreIfJumped, 120);
        editorScrollView.postDelayed(restoreIfJumped, 260);
        if (extendedProtection) {
            // 首次获得焦点时，软键盘与 250ms 入场动画可能在更晚的布局帧再次触发滚动。
            editorScrollView.postDelayed(restoreIfJumped, 420);
            editorScrollView.postDelayed(restoreIfJumped, 700);
        }
    }

    private void jumpEditorToOffset(TextView textView, int target) {
        if (target < 0 || target > textView.length()) return;
        // 序号只负责导航，不移动 EditText 光标；否则系统会再次执行 bringPointIntoView，
        // 把外层 ScrollView 拉回序号所在的顶部区域，并让序号呈现被选中的状态。
        jumpAndFlash(textView, target, editorScrollView);
        Runnable keepTargetVisible = () -> {
            Layout layout = textView.getLayout();
            if (layout == null || editorScrollView == null) return;
            int safeTarget = Math.max(0, Math.min(target, textView.length()));
            int line = layout.getLineForOffset(safeTarget);
            int y = layout.getLineTop(line);
            editorScrollView.scrollTo(0, Math.max(0, y - editorScrollView.getHeight() / 3));
        };
        editorScrollView.post(keepTargetVisible);
        editorScrollView.postDelayed(keepTargetVisible, 120);
        editorScrollView.postDelayed(keepTargetVisible, 260);
    }

    private void purgeDeadClauseMarkers(Editable editable) {
        isEditorSelfModifying = true;
        try {
            List<ListMarkerSpan> delete = new ArrayList<>(); for (ClauseLink link : currentClauseLinks) if (link.isDead && editable.getSpanStart(link.listMarkerSpan) >= 0) delete.add(link.listMarkerSpan);
            delete.sort((a, b) -> Integer.compare(editable.getSpanStart(b), editable.getSpanStart(a)));
            for (ListMarkerSpan span : delete) {
                int start = editable.getSpanStart(span), end = editable.getSpanEnd(span); if (start < 0 || end < 0) continue;
                while (start > 0 && editable.charAt(start - 1) != '\n') start--; while (end < editable.length() && editable.charAt(end) != '\n') end++; if (end < editable.length()) end++; editable.delete(start, end);
            }
        } finally { isEditorSelfModifying = false; }
    }

    @SuppressLint("ClickableViewAccessibility")
    private void setupOutputLongPress() {
        outputText.setOnTouchListener(new View.OnTouchListener() {
            boolean triggered; float startX, startY, rawX, rawY;
            final Runnable longPress = () -> {
                String current = outputText.getText().toString(); if (current.isEmpty() || "正在加载...".equals(current) || "已加载。".equals(current) || isCheckingMain || lastEditorSpannable == null) return;
                triggered = true; outputText.performHapticFeedback(android.view.HapticFeedbackConstants.LONG_PRESS);
                ViewGroup parent = (ViewGroup) scrollView.getParent(); int[] location = new int[2]; parent.getLocationOnScreen(location); int centerX = (int) (rawX - location[0]), centerY = (int) (rawY - location[1]);
                View ripple = new View(MainActivity.this); ripple.setBackgroundColor(Color.parseColor("#20000000")); ripple.setVisibility(View.INVISIBLE); parent.addView(ripple, new ViewGroup.LayoutParams(-1, -1));
                float radius = (float) Math.hypot(Math.max(centerX, parent.getWidth() - centerX), Math.max(centerY, parent.getHeight() - centerY)); Animator reveal = ViewAnimationUtils.createCircularReveal(ripple, centerX, centerY, 0, radius); reveal.setDuration(350); ripple.setVisibility(View.VISIBLE); reveal.start();
                reveal.addListener(new AnimatorListenerAdapter() { @Override public void onAnimationEnd(Animator animation) { parent.removeView(ripple); openEditor(); } });
            };
            @Override public boolean onTouch(View v, MotionEvent event) {
                switch (event.getActionMasked()) {
                    case MotionEvent.ACTION_DOWN: triggered = false; startX = event.getX(); startY = event.getY(); rawX = event.getRawX(); rawY = event.getRawY(); AppExecutors.MAIN.removeCallbacks(longPress); AppExecutors.MAIN.postDelayed(longPress, 600); break;
                    case MotionEvent.ACTION_MOVE: if (!triggered && (Math.abs(event.getX() - startX) > 20 || Math.abs(event.getY() - startY) > 20)) AppExecutors.MAIN.removeCallbacks(longPress); break;
                    case MotionEvent.ACTION_UP: case MotionEvent.ACTION_CANCEL: AppExecutors.MAIN.removeCallbacks(longPress); if (triggered) return true;
                }
                return false;
            }
        });
    }

    private void openEditor() {
        originalIsManuallyEdited = isManuallyEditedOut; if (isManuallyEditedOut) { lastEditorSpannable = new SpannableStringBuilder(outputText.getText()); normalizePortableJumpSpans(lastEditorSpannable); } if (lastEditorSpannable == null) return;
        originalEditorText = lastEditorSpannable.toString(); isEditorSelfModifying = true; expandedEditText.setText(lastEditorSpannable);
        if (isManuallyEditedOut) rebindPortableJumpsForEditor(expandedEditText.getText());
        isEditorSelfModifying = false; editorUndoStack.clear(); editorRedoStack.clear(); firstEditorCursorTapPending = true; drawerLayout.setDrawerLockMode(DrawerLayout.LOCK_MODE_LOCKED_CLOSED);
        expandedEditorOverlay.setAlpha(0); expandedEditorOverlay.setTranslationY(150); expandedEditorOverlay.setVisibility(View.VISIBLE); expandedEditorOverlay.animate().alpha(1).translationY(0).setDuration(250).start(); Toast.makeText(this, "进入编辑模式：波浪线为系统或你修改过的文字。", Toast.LENGTH_SHORT).show(); isEditorOpen = true;
    }

    private void applyEditorChanges() {
        if (!expandedEditText.getText().toString().equals(originalEditorText)) {
            isManuallyEditedOut = true;
            SpannableStringBuilder snapshot = new SpannableStringBuilder(expandedEditText.getText());
            normalizePortableJumpSpans(snapshot);
            lastEditorSpannable = new SpannableStringBuilder(snapshot);
            outputText.setText(snapshot); outputText.setMovementMethod(MyLinkMovementMethod.getInstance()); outputText.setHighlightColor(Color.TRANSPARENT);
            if (lastSavedHistoryFileId != null) { HistoryStore.saveManual(this, lastSavedHistoryFileId, snapshot); saveHistory(extractCleanTextFromSpanned(snapshot), lastSavedHistoryFileId); }
        }
        closeEditor();
    }

    private void closeEditor() {
        firstEditorCursorTapPending = false;
        expandedEditorOverlay.animate().alpha(0).translationY(150).setDuration(250).withEndAction(() -> { expandedEditorOverlay.setVisibility(View.GONE); drawerLayout.setDrawerLockMode(DrawerLayout.LOCK_MODE_UNLOCKED); isEditorOpen = false; }).start();
    }

    private void applyIndent() {
        Editable editable = expandedEditText.getText(); if (editable == null || editable.length() == 0) return;
        pushState(editorUndoStack, new EditorState(new SpannableStringBuilder(editable), expandedEditText.getSelectionStart())); String text = editable.toString(); List<int[]> replacements = new ArrayList<>();
        int contentStart = 0, index = text.indexOf("【修正后的全文】\n"); if (index >= 0) contentStart = index + 9; else { index = text.indexOf("【原文】\n"); if (index >= 0) contentStart = index + 5; }
        int lineStart = contentStart;
        while (lineStart < text.length()) {
            int lineEnd = text.indexOf('\n', lineStart); if (lineEnd < 0) lineEnd = text.length(); String line = text.substring(lineStart, lineEnd).trim();
            if (!(line.startsWith("［文档") && line.endsWith("］"))) { int first = lineStart; while (first < lineEnd && (text.charAt(first) == ' ' || text.charAt(first) == '\t' || text.charAt(first) == '\u3000')) first++; if (first <= lineEnd) replacements.add(new int[]{lineStart, first}); }
            lineStart = lineEnd + 1;
        }
        isEditorSelfModifying = true;
        for (int i = replacements.size() - 1; i >= 0; i--) { int[] range = replacements.get(i); if (range[0] == range[1] && range[0] < editable.length() && editable.charAt(range[0]) == '\n') continue; editable.replace(range[0], range[1], range[0] == range[1] && range[0] >= editable.length() ? "" : "　　"); }
        isEditorSelfModifying = false; Toast.makeText(this, "已添加首行缩进", Toast.LENGTH_SHORT).show();
    }

    private void restoreEditorState(Stack<EditorState> source, Stack<EditorState> destination, boolean undo) {
        if (source.isEmpty()) return; int scrollY = editorScrollView.getScrollY(); pushState(destination, new EditorState(new SpannableStringBuilder(expandedEditText.getText()), expandedEditText.getSelectionStart())); EditorState state = source.pop();
        isEditorSelfModifying = true; expandedEditText.setText(state.text); isEditorSelfModifying = false; expandedEditText.setSelection(Math.max(0, Math.min(state.selectionStart, expandedEditText.length()))); editorScrollView.post(() -> editorScrollView.scrollTo(0, Math.max(0, scrollY)));
        if (undo && state.text.toString().equals(originalEditorText)) { isManuallyEditedOut = originalIsManuallyEdited; if (!isManuallyEditedOut) { renderFinalBlocks(); isEditorSelfModifying = true; expandedEditText.setText(lastEditorSpannable); isEditorSelfModifying = false; } }
    }

    private void updateInputEditorWordCount() {
        if (tvInputEditorWordCount == null || expandedInputEditText == null) return;
        int withPunctuation = inputCounts.with;
        int withoutPunctuation = inputCounts.without;
        tvInputEditorWordCount.setText(withPunctuation + " ｜ " + withoutPunctuation + " 字");
    }

    private void setupInputEditor() {
        Button indent = findViewById(R.id.btnInputEditorIndent), undo = findViewById(R.id.btnInputEditorUndo), redo = findViewById(R.id.btnInputEditorRedo), done = findViewById(R.id.btnInputEditorDone);
        View inputTouch = findViewById(R.id.inputEditorScrollTouchArea);
        if (inputTouch != null) inputTouch.setOnTouchListener((v, event) -> {
            android.text.Layout layout = expandedInputEditText.getLayout();
            int contentHeight = layout == null ? expandedInputEditText.getHeight() : layout.getHeight() + expandedInputEditText.getTotalPaddingTop() + expandedInputEditText.getTotalPaddingBottom();
            int max = Math.max(0, contentHeight - expandedInputEditText.getHeight());
            if (max > 0 && v.getHeight() > 0) {
                float y = Math.max(0f, Math.min(event.getY(), v.getHeight()));
                expandedInputEditText.scrollTo(0, (int) (y / v.getHeight() * max));
            }
            return true;
        });
        inputCounts.reset(expandedInputEditText.getText());
        expandedInputEditText.addTextChangedListener(new TextWatcher() {
            @Override public void beforeTextChanged(CharSequence s, int start, int count, int after) {
                inputCounts.before(s, start, count);
                if (isInputEditorSelfModifying) return;
                pushInputEdit(inputUndoStack, new InputEdit(s, start, count, after, expandedInputEditText.getSelectionStart())); inputRedoStack.clear();
            }
            @Override public void onTextChanged(CharSequence s, int start, int before, int count) { inputCounts.after(s, before, count); }
            @Override public void afterTextChanged(Editable editable) {
                if (isInputEditorSelfModifying) return;
                updateInputEditorWordCount();
                inputEditorSyncDirty = true;
                inputSyncHandler.removeCallbacks(inputEditorSync); inputSyncHandler.postDelayed(inputEditorSync, 400);
                if (editable.length() > 0 && !currentIsFast) warmProEngineAsync(MainActivity.this);
            }
        });
        done.setOnClickListener(v -> closeInputEditor(true));
        indent.setOnClickListener(v -> applyInputIndent());
        undo.setOnClickListener(v -> restoreInputEditorState(inputUndoStack, inputRedoStack));
        redo.setOnClickListener(v -> { if (inputRedoStack.isEmpty()) Toast.makeText(this, "没有可还原的操作", Toast.LENGTH_SHORT).show(); else restoreInputEditorState(inputRedoStack, inputUndoStack); });
    }

    private void openInputEditor() {
        if (inputEditorOverlay == null || expandedInputEditText == null) return;
        inputSyncHandler.removeCallbacksAndMessages(null);
        originalInputEditorText = inputText.getText().toString();
        int selection = Math.max(0, Math.min(inputText.getSelectionStart(), originalInputEditorText.length()));
        isInputEditorSelfModifying = true; expandedInputEditText.setText(originalInputEditorText); expandedInputEditText.setSelection(selection); isInputEditorSelfModifying = false;
        inputUndoStack.clear(); inputRedoStack.clear(); updateInputEditorWordCount();
        drawerLayout.setDrawerLockMode(DrawerLayout.LOCK_MODE_LOCKED_CLOSED); inputEditorOverlay.setAlpha(0f); inputEditorOverlay.setTranslationY(100f); inputEditorOverlay.setVisibility(View.VISIBLE); inputEditorOverlay.animate().alpha(1f).translationY(0f).setDuration(180).start(); isInputEditorOpen = true;
        expandedInputEditText.requestFocus(); expandedInputEditText.post(() -> { android.view.inputmethod.InputMethodManager imm = (android.view.inputmethod.InputMethodManager) getSystemService(INPUT_METHOD_SERVICE); if (imm != null) imm.showSoftInput(expandedInputEditText, android.view.inputmethod.InputMethodManager.SHOW_IMPLICIT); });
    }

    private void closeInputEditor(boolean keepChanges) {
        if (!isInputEditorOpen || inputEditorOverlay == null) return;
        inputSyncHandler.removeCallbacksAndMessages(null); inputEditorSyncDirty = false; mainSyncDirty = false;
        if (keepChanges) {
            String value = expandedInputEditText.getText().toString(); int selection = Math.max(0, Math.min(expandedInputEditText.getSelectionStart(), value.length()));
            if (!value.equals(originalInputEditorText)) invalidateDisplayedResultForInputChange(value);
            boolean old = isRestoringHistory; isRestoringHistory = true; inputText.setText(value); inputText.setSelection(Math.max(0, Math.min(selection, inputText.length()))); isRestoringHistory = old; DraftSync.publish(sp, value);
        } else {
            DraftSync.publish(sp, originalInputEditorText);
        }
        android.view.inputmethod.InputMethodManager imm = (android.view.inputmethod.InputMethodManager) getSystemService(INPUT_METHOD_SERVICE); if (imm != null) imm.hideSoftInputFromWindow(expandedInputEditText.getWindowToken(), 0);
        isInputEditorOpen = false;
        inputSyncHandler.removeCallbacksAndMessages(null); mainSyncDirty = false;
        inputEditorOverlay.animate().alpha(0f).translationY(100f).setDuration(160).withEndAction(() -> {
            inputEditorOverlay.setVisibility(View.GONE); drawerLayout.setDrawerLockMode(DrawerLayout.LOCK_MODE_UNLOCKED);
            inputUndoStack.clear(); inputRedoStack.clear(); originalInputEditorText = "";
            isInputEditorSelfModifying = true; expandedInputEditText.setText(""); isInputEditorSelfModifying = false;
        }).start();
    }

    private void confirmCloseInputEditor() {
        if (!isInputEditorOpen) return;
        String current = expandedInputEditText == null ? "" : expandedInputEditText.getText().toString();
        String original = originalInputEditorText == null ? "" : originalInputEditorText;
        // 原输入框为空时，没有旧内容需要保护：返回键直接保存当前输入，不再弹确认。
        if (original.isEmpty()) { closeInputEditor(true); return; }
        if (current.equals(original)) { closeInputEditor(false); return; }
        new android.app.AlertDialog.Builder(this)
                .setMessage("是否保存刚才的编辑操作？")
                .setPositiveButton("是", (dialog, which) -> closeInputEditor(true))
                .setNegativeButton("否", (dialog, which) -> closeInputEditor(false))
                .show();
    }

    private void applyInputIndent() {
        Editable editable = expandedInputEditText.getText(); if (editable == null || editable.length() == 0) return;
        String text = editable.toString(); String[] lines = text.split("\\n", -1); StringBuilder out = new StringBuilder(text.length() + lines.length * 2);
        for (int i = 0; i < lines.length; i++) { String line = lines[i]; int first = 0; while (first < line.length() && (line.charAt(first) == ' ' || line.charAt(first) == '\t' || line.charAt(first) == '\u3000')) first++; if (first < line.length()) out.append("　　").append(line.substring(first)); if (i + 1 < lines.length) out.append('\n'); }
        pushInputEdit(inputUndoStack, new InputEdit(editable, 0, editable.length(), out.length(), expandedInputEditText.getSelectionStart())); inputRedoStack.clear();
        inputSyncHandler.removeCallbacks(inputEditorSync); inputEditorSyncDirty = false;
        isInputEditorSelfModifying = true; expandedInputEditText.setText(out.toString()); expandedInputEditText.setSelection(expandedInputEditText.length()); isInputEditorSelfModifying = false; updateInputEditorWordCount(); DraftSync.publish(sp, out.toString());
    }

    private void restoreInputEditorState(Stack<InputEdit> source, Stack<InputEdit> destination) {
        if (source.isEmpty()) return;
        Editable text = expandedInputEditText.getText(); InputEdit edit = source.pop();
        pushInputEdit(destination, new InputEdit(text, edit.start, edit.insertedLength, edit.removed.length(), expandedInputEditText.getSelectionStart()));
        isInputEditorSelfModifying = true;
        text.replace(edit.start, edit.start + edit.insertedLength, edit.removed);
        expandedInputEditText.setSelection(Math.max(0, Math.min(edit.selectionStart, expandedInputEditText.length())));
        isInputEditorSelfModifying = false; updateInputEditorWordCount();
        inputSyncHandler.removeCallbacks(inputEditorSync); inputEditorSyncDirty = true; inputEditorSync.run();
    }

    private boolean hasDisplayedCorrectionResult() {
        return isManuallyEditedOut || (allSentencesBlocks != null && !allSentencesBlocks.isEmpty());
    }

    private void setResultStaleWarning(boolean stale) {
        displayedResultStale = stale;
        if (!stale) displayedResultInput = hasDisplayedCorrectionResult() && inputText != null ? inputText.getText().toString() : null;
        if (tvResultStaleWarning != null) tvResultStaleWarning.setVisibility(stale ? View.VISIBLE : View.GONE);
    }

    private void invalidateDisplayedResultForInputChange() { invalidateDisplayedResultForInputChange(inputText.getText().toString()); }
    private void invalidateDisplayedResultForInputChange(String nextText) {
        historyRestoreGeneration++;
        if (isCheckingMain) {
            cancelMainCheck();
            allSentencesBlocks.clear();
            isManuallyEditedOut = false;
            lastEditorSpannable = null;
            currentClauseLinks.clear();
            setResultStaleWarning(false);
        } else {
            boolean hadResult = hasDisplayedCorrectionResult();
            btnCheck.setText("开始纠错");
            setResultStaleWarning(DraftSync.resultIsStale(nextText, displayedResultInput, hadResult));
            // 保留旧纠错结果供对照；它已被明确标记为“对应修改前原文”。
            // 新一轮纠错始终使用当前输入框文本，不允许旧结果回写覆盖新文本。
        }
        lastSavedHistoryFileId = null;
    }

    private void setupInputWatcher() {
        inputText.addTextChangedListener(new TextWatcher() {
            int visibleCount = countLettersOrDigits(inputText.getText(), 0, inputText.length());
            int removedCount;
            String removedText = ""; boolean actualChange;
            final Runnable update = () -> {
                String value = inputText.getText().toString();
                DraftSync.publish(sp, value); mainSyncDirty = false;
            };

            @Override public void beforeTextChanged(CharSequence s, int start, int count, int after) {
                removedCount = countLettersOrDigits(s, start, start + count);
                removedText = s.subSequence(start, start + count).toString();
            }

            @Override public void onTextChanged(CharSequence s, int start, int before, int count) {
                actualChange = DraftSync.contentChanged(removedText, s, start, count);
                int addedCount = countLettersOrDigits(s, start, start + count);
                visibleCount = Math.max(0, visibleCount - removedCount + addedCount);
                if (actualChange && count > 2 && !isRestoringHistory && !isCleanDialogOpen) {
                    String chunk = s.subSequence(start, start + count).toString();
                    if (hasSymbolBurst(chunk)) AppExecutors.MAIN.post(() -> checkAndPromptCleanup(MainActivity.this, inputText.getText().toString(), cleaned -> {
                        if (!cleaned.equals(inputText.getText().toString())) { invalidateDisplayedResultForInputChange(cleaned); boolean old = isRestoringHistory; isRestoringHistory = true; inputText.setText(cleaned); inputText.setSelection(cleaned.length()); DraftSync.publish(sp, cleaned); isRestoringHistory = old; }
                    }));
                }
            }

            @Override public void afterTextChanged(Editable editable) {
                btnSaveTxt.setEnabled(editable.length() > 0);
                boolean changed = actualChange; actualChange = false;
                if (!changed) return;
                cancelImport();
                if (!isRestoringHistory) invalidateDisplayedResultForInputChange();
                if (editable.length() > 0 && !currentIsFast) warmProEngineAsync(MainActivity.this);
                tvWordCount.setText(visibleCount + " 字");
                // The external draft already lives in DraftSync; never republish an old copy later.
                if (applyingExternalDraft) return;
                mainSyncDirty = true;
                inputSyncHandler.removeCallbacks(update); inputSyncHandler.postDelayed(update, 400);
            }
        });
    }

    private static boolean ensureProEngineLoadedLocked(Context context) {
        try {
            Context appContext = context.getApplicationContext();
            loadIdlePolicy(appContext);
            if (!proVocabReady) loadCharVocab(appContext, "sys_vocab_p.dat");
            if (proModule == null) proModule = loadDecryptedModule(appContext, "sys_core_p.dat", "hcam_v2_five_int8", PRO_MODEL_LOCK);
            return proModule != null;
        } catch (Throwable error) {
            SecureAsset.recordError("HCAM 专业模型加载失败", error);
            return false;
        }
    }

    private static void scheduleProEngineReleaseLocked() {
        PRO_MODEL_HANDLER.removeCallbacks(PRO_MODEL_RELEASE_TASK);
        if (proModuleUsers == 0 && proModule != null) PRO_MODEL_HANDLER.postDelayed(PRO_MODEL_RELEASE_TASK, PRO_IDLE.remaining(android.os.SystemClock.uptimeMillis()));
    }

    // 恢复旧版预热体验：专业模式下输入变化/切换模式时后台加载 HCAM，首次纠错无需等待模型冷启动。
    public static void warmProEngineAsync(Context context) {
        if (context == null) return;
        PRO_IDLE.activity(android.os.SystemClock.uptimeMillis());
        if (proModule != null) return;
        if (!proWarmQueued.compareAndSet(false, true)) return;
        Context appContext = context.getApplicationContext();
        AppExecutors.INFERENCE.execute(() -> {
            try { synchronized (PRO_MODEL_LOCK) { if(!ensureProEngineLoadedLocked(appContext)) showModelError("模型预热失败："+SecureAsset.lastErrorSummary()); scheduleProEngineReleaseLocked(); } }
            finally { proWarmQueued.set(false); }
        });
    }

    public static void noteProCorrectionStart(Context context) {
        if (context == null) return;
        loadIdlePolicy(context.getApplicationContext());
        boolean adjusted = PRO_IDLE.correctionStarted(android.os.SystemClock.uptimeMillis());
        if (adjusted) persistIdlePolicy();
    }

    public static boolean acquireProEngine(Context context) {
        loadIdlePolicy(context.getApplicationContext());
        PRO_IDLE.activity(android.os.SystemClock.uptimeMillis());
        synchronized (PRO_MODEL_LOCK) {
            PRO_MODEL_HANDLER.removeCallbacks(PRO_MODEL_RELEASE_TASK);
            if (!ensureProEngineLoadedLocked(context)) return false;
            proModuleUsers++;
            return true;
        }
    }

    public static void releaseProEngine() {
        synchronized (PRO_MODEL_LOCK) {
            if (proModuleUsers > 0) proModuleUsers--;
            PRO_IDLE.correctionFinished(android.os.SystemClock.uptimeMillis());
            persistIdlePolicy();
            scheduleProEngineReleaseLocked();
        }
    }

    private static void releaseProEngineNowIfIdle() {
        synchronized (PRO_MODEL_LOCK) {
            if (proModuleUsers != 0 || proModule == null) return;
            persistIdlePolicy();
            long remaining = PRO_IDLE.remaining(android.os.SystemClock.uptimeMillis());
            if (remaining > 0) { PRO_MODEL_HANDLER.postDelayed(PRO_MODEL_RELEASE_TASK, remaining); return; }
            ModelEngine module = proModule;
            proModule = null;
            try {
                module.close();
                android.util.Log.i("DededeModel", "专业模型空闲，已释放 Native Module 内存；当前等待 " + (PRO_IDLE.timeout() / 1000) + " 秒");
            } catch (Throwable error) {
                SecureAsset.recordError("HCAM 专业模型释放失败", error);showModelError(SecureAsset.lastErrorSummary());
            } finally {
                File plain = proPlainModelFile;
                proPlainModelFile = null;
                if (plain != null && plain.exists() && !plain.delete()) {
                    android.util.Log.w("DededeModel", "临时明文模型删除失败，将在后续启动时再次清理：" + plain);
                }
            }
        }
    }

    private void showHelp() {
        String text = "【模式介绍】\n极速：不调用神经网络检查“的/地/得/做/作”；仅运行系统内置的错词库和规则。速度最快（毫秒级），适合只想快速检查错别字与语病的场景。\n\n专业：比极速模式额外纠错“的地得做作”使用，速度较快（秒级）。\nHCAM模型是本作者自己设计，并从零训练＋微调的中文掩码模型。该模型会额外纠错“的地得”和“做作”。\n通常建议始终使用专业模式，除非你对“的地得做作”运用得如火纯青。\n\n注：不同手机的速度会有差异；模型也可能出现极少量误判，这是神经网络的通病，在所难免。\n\n单次纠错不建议超过30万字，可能会出现卡顿或闪退。\n\n【温度参数（仅专业模式）】\n控制AI判断的自信（果断）程度。\n• 允许范围：0.5～2.0；推荐默认值1.0。\n• 温度值越高，概率分布越平缓，模型更保守，给出的置信度变低，修改量可能下降。\n• 值越低（如0.5）：概率分布越尖锐，模型更激进，给出的置信度更高，修改量可能上升。\n• 值越高（如2.0）：概率分布越平缓，模型更保守，修改量可能下降。\n举例：0.8会给出更高的置信度，更不容易被阈值拦截。1.2会更保守，更容易被阈值拦截。\n• 温度不得低于0.5或高于2.0。\n\n【置信度拦截阈值（仅专业模式）】\n只有AI的置信度 ≥ 阈值时才修改，否则保留原字，防止过度纠错。\n• 推荐默认值：的0.7、地0.7、得0.75、做0.75、作0.75。阈值按模型预测的目标字应用，范围0～1。\n举例：设置为0.9时，模型修改的置信度超过0.9才会被保留并显示，否则忽略。\n\n【交互与拓展功能】\n• 手动修改：检查后，点击带下划线的字词即可手动修改或还原。\n• 纠错过程中修改原文会中断检查。\n• 输入框展开：点击输入框右上角的展开按钮，可进入全屏输入编辑，支持可拖动滚动条、撤销、还原和首行缩进；完成后内容会自动同步回主输入框。\n• 便签模式：长按底部纠错结果区域，即可展开便签编辑器进行全局修改，完成后支持直接导出。绿色的波浪线为系统或你修改过的文本（原在输出框中呈现红色）。\n• 字体大小与皮肤：点击标题栏“A”进入字体设置，可调节字体大小。底部彩色衣服可切换不同的界面皮肤。\n• 快速跳转：点击纠错清单中的序号 [1]，可以自动滚动定位至全文对应段落。\n• 一键粘贴：点击按钮快速读取剪贴板内容。（不建议一次性粘贴超过20万字，可能导致闪退）\n• 导入文件：支持txt、md、docx、pdf及图片格式(支持直接OCR识图)。\n  不建议一次导入多个过大的文件，可能导致使用卡顿。也不建议导入带有特定格式和排版（如表格类）的文件，会破坏原有排版。\n\n• 系统分享：在其他App中选中文本，点击分享并选择本App，即可跳转至系统进行纠错。\n• 历史记录：最多保存近50条。\n\n 【错词库】\n  手动定义规则，这些规则会在纠错中自动应用。\n  使用方法：\n1.白名单：\n在“原始文本”框输入例如“慢慢的”或“张三”，直接提交。等效于白名单，系统在遇到该词后不会再修改。\n  2.改错：在“修改后”里再添加文本（如：慢慢地），纠错时原始文本就会被自动修改。\n• 自定义规则优先级高于本系统。\n\n【悬浮窗】\n开启后支持后台随时随地纠错。长按悬浮球或点击面板右上角可同步至应用内继续操作。点击面板外可自动收起。\n\n【标点清理：】\n  当检测到包含复制残留的垃圾标点时会触发弹窗，允许自由清理提纯文本。\n\n• 其他：本App和内置模型均由 奇 制作与训练，非其他开源模型，无版权风险。本著作权归奇（qi）所有。想与作者私聊？公众号搜索：Li的信箱";
        int ui = Math.max(-3, Math.min(3, sp.getInt("font_offset_sys", 0))); TextView view = new TextView(this); view.setText(text); view.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP, 14 + ui); view.setTextColor(0xFF333333); view.setLineSpacing(0, 1.2f); int padding = (int) (20 * getResources().getDisplayMetrics().density); view.setPadding(padding, padding / 2, padding, 0); ScrollView scroll = new ScrollView(this); scroll.addView(view); new AlertDialog.Builder(this).setTitle("使用说明").setView(scroll).setPositiveButton("知道了", null).show();
    }

    private void setupMainButtons() {
        btnImport.setOnClickListener(v -> { Toast.makeText(this, "支持 txt、md、docx、pptx、pdf 及各种图片格式。（最多上传20个）", Toast.LENGTH_SHORT).show(); openFilePicker(); });
        btnPaste.setOnClickListener(v -> {
            ClipboardManager clipboard = (ClipboardManager) getSystemService(CLIPBOARD_SERVICE);
            if (clipboard != null && clipboard.hasPrimaryClip() && clipboard.getPrimaryClip().getItemCount() > 0) { CharSequence value = clipboard.getPrimaryClip().getItemAt(0).getText(); if (value != null) checkAndPromptCleanup(this, value.toString(), cleaned -> { lastSavedHistoryFileId = null; inputText.setText(cleaned); DraftSync.publish(sp, cleaned); }); }
        });
        btnClear.setOnClickListener(v -> { cancelImport(); cancelMainCheck(); lastSavedHistoryFileId = null; inputText.setText(""); allSentencesBlocks.clear(); outputText.setText(""); isManuallyEditedOut = false; setResultStaleWarning(false); btnCopy.setEnabled(false); btnSaveTxt.setEnabled(false); isCheckingMain = false; });
        btnCheck.setOnClickListener(v -> {
            InputMethodManager manager = (InputMethodManager) getSystemService(INPUT_METHOD_SERVICE); if (manager != null) manager.hideSoftInputFromWindow(v.getWindowToken(), 0);
            if (isCheckingMain) { cancelMainCheck(); return; }
            Runnable execute = () -> beginCheck();
            if (isManuallyEditedOut && !displayedResultStale) {
                CharSequence displayed = outputText.getText();
                String editedText = displayed instanceof Spanned ? extractCleanTextFromSpanned((Spanned) displayed) : displayed.toString();
                if (editedText.trim().isEmpty()) {
                    isManuallyEditedOut = false;
                    execute.run();
                } else {
                    new AlertDialog.Builder(this).setMessage("是否使用编辑后的文本继续纠错？\n（否则用原始文本）")
                            .setPositiveButton("是", (d, w) -> { inputText.setText(editedText); execute.run(); })
                            .setNegativeButton("否", (d, w) -> execute.run())
                            .show();
                }
            } else execute.run();
        });
        btnCopy.setOnClickListener(v -> {
            String value = isManuallyEditedOut ? extractCleanTextFromSpanned((Spanned) outputText.getText()) : getCleanTextStatic(); if (value.isEmpty()) return;
            ClipboardManager clipboard = (ClipboardManager) getSystemService(CLIPBOARD_SERVICE); if (clipboard != null) clipboard.setPrimaryClip(ClipData.newPlainText("Corrected Article", value)); Toast.makeText(this, "已复制修正后的全文。", Toast.LENGTH_SHORT).show();
        });
        btnSaveTxt.setOnClickListener(v -> chooseSaveFormat());
    }

    private void beginCheck() {
        if (inputText.length() == 0) { Toast.makeText(this, "文本为空", Toast.LENGTH_SHORT).show(); return; }
        autoScrollEnabled = true;
        isManuallyEditedOut = false;
        setResultStaleWarning(false);
        allSentencesBlocks.clear();
        lastEditorSpannable = null;
        currentClauseLinks.clear();

        boolean fast = rbFast.isChecked();
        float temperature = 1f;
        if (!fast) {
            temperature = parseFloatSafe(editTemp.getText().toString(), Float.NaN);
            if (!isTemperatureValid(temperature)) {
                temperature = 1.0f;
                editTemp.setText("1.0");
                sp.edit().putString("pro_temp", "1.0").apply();
                Toast.makeText(this, "温度参数无效，已自动恢复为1.0（允许范围0.5～2.0）", Toast.LENGTH_LONG).show();
            }
        }
        saveSettings(currentIsFast);

        String raw = inputText.getText().toString();
        if (raw.isEmpty()) return;

        hasStartedChecking = true;
        if (lastSavedHistoryFileId == null) lastSavedHistoryFileId = java.util.UUID.randomUUID().toString();
        saveHistory(raw, lastSavedHistoryFileId);
        isCheckingMain = true;
        btnCheck.setText("取消");
        doInference(fast, temperature);
    }

    private void chooseSaveFormat() {
        String raw = inputText.getText().toString(); if (raw.isEmpty()) return;
        String[] options = {"TXT 纯文本", "MD 文档", "PDF 文档", "DOCX 文档", "JPG 图片", "PNG 图片"};
        new AlertDialog.Builder(this).setTitle("选择保存格式").setItems(options, (dialog, which) -> {
            saveFormat = which; String text = isManuallyEditedOut ? extractCleanTextFromSpanned((Spanned) outputText.getText()) : getCleanTextStatic(); boolean corrected = false;
            if (text.isEmpty()) { text = raw; Toast.makeText(this, "未开始纠错，将保存原始文本为" + options[which].split(" ")[0] + "格式", Toast.LENGTH_LONG).show(); }
            else if (isManuallyEditedOut) corrected = true; else outer: for (List<TextBlock> sentence : allSentencesBlocks) for (TextBlock block : sentence) if (block.isMutable && !block.current.equals(block.original)) { corrected = true; break outer; }
            pendingSaveText = text; Intent intent = new Intent(Intent.ACTION_CREATE_DOCUMENT); intent.addCategory(Intent.CATEGORY_OPENABLE); String name = corrected ? "纠错结果" : "原始文本";
            if (which == 0) { intent.setType("text/plain"); intent.putExtra(Intent.EXTRA_TITLE, name + ".txt"); } else if (which == 1) { intent.setType("text/markdown"); intent.putExtra(Intent.EXTRA_TITLE, name + ".md"); } else if (which == 2) { intent.setType("application/pdf"); intent.putExtra(Intent.EXTRA_TITLE, name + ".pdf"); } else if (which == 3) { intent.setType("application/vnd.openxmlformats-officedocument.wordprocessingml.document"); intent.putExtra(Intent.EXTRA_TITLE, name + ".docx"); } else if (which == 4) { intent.setType("image/jpeg"); intent.putExtra(Intent.EXTRA_TITLE, name + ".jpg"); } else { intent.setType("image/png"); intent.putExtra(Intent.EXTRA_TITLE, name + ".png"); }
            try { startActivityForResult(intent, 101); } catch (Exception exception) { Toast.makeText(this, "调起失败: " + exception.getMessage(), Toast.LENGTH_SHORT).show(); }
        }).show();
    }

    private void setupDrawerButtons() {
        Button add = findViewById(R.id.btnAddTypo); EditText original = findViewById(R.id.etOriginal), corrected = findViewById(R.id.etCorrected);
        add.setOnClickListener(v -> {
            String source = original.getText().toString().trim(), target = corrected.getText().toString().trim(); if (source.isEmpty()) { Toast.makeText(this, "原始文本不能为空", Toast.LENGTH_SHORT).show(); return; } if (target.isEmpty()) target = source;
            try {
                JSONObject object = new JSONObject(sp.getString("custom_typos", "{}")); if (editingTypoKey != null && !editingTypoKey.equals(source)) object.remove(editingTypoKey); object.put(source, target); sp.edit().putString("custom_typos", object.toString()).apply(); reloadTypoMapAsync(this); renderCustomTyposUI(); original.setText(""); original.setHint("原始文本"); corrected.setText(""); TextView whitelistHint = findViewById(R.id.tvWhitelistJumpHint); if (whitelistHint != null) whitelistHint.setVisibility(View.GONE); editingTypoKey = null; add.setText("添加"); Toast.makeText(this, "保存成功", Toast.LENGTH_SHORT).show();
            } catch (Exception ignored) {}
        });
        findViewById(R.id.btnClearHistory).setOnClickListener(v -> new AlertDialog.Builder(this).setMessage("是否清空全部历史记录？").setPositiveButton("是", (d, w) -> {
            HistoryStore.clear(this); sp.edit().putString("history_records", "[]").apply(); lastSavedHistoryFileId = null; isManuallyEditedOut = false; boolean old = isRestoringHistory; isRestoringHistory = true; inputText.setText(""); isRestoringHistory = old; allSentencesBlocks.clear(); outputText.setText(""); setResultStaleWarning(false); btnCheck.setText("开始纠错"); btnCopy.setEnabled(false); btnSaveTxt.setEnabled(false); renderHistoryUI(); Toast.makeText(this, "历史记录已全部清空", Toast.LENGTH_SHORT).show();
        }).setNegativeButton("否", null).show());
    }

    private void renderCustomTyposUI() {
        FlowLayout container = findViewById(R.id.llCustomTypos); Button expand = findViewById(R.id.btnExpandTypos), add = findViewById(R.id.btnAddTypo); EditText original = findViewById(R.id.etOriginal), corrected = findViewById(R.id.etCorrected); container.removeAllViews();
        try {
            JSONObject object = new JSONObject(sp.getString("custom_typos", "{}")); Iterator<String> keys = object.keys(); List<String[]> items = new ArrayList<>(); while (keys.hasNext()) { String key = keys.next(); items.add(new String[]{key, object.getString(key)}); }
            int count = isTyposExpanded ? items.size() : Math.min(items.size(), 15);
            for (int i = 0; i < count; i++) {
                String[] item = items.get(i); TextView view = new TextView(this); view.setText(item[0].equals(item[1]) ? item[0] : item[0] + " → " + item[1]); view.setPadding(16, 16, 16, 16); view.setTextSize(14f + Math.max(-3, Math.min(3, sp.getInt("font_offset_sys", 0)))); view.setTextColor(0xFF4CAF50); view.setBackgroundResource(R.drawable.item_bg_selector); view.setClickable(true);
                view.setOnClickListener(v -> new AlertDialog.Builder(this).setTitle("操作错词").setMessage(item[0].equals(item[1]) ? "白名单：" + item[0] : "原始：" + item[0] + "\n修改后：" + item[1]).setPositiveButton("删除", (d, w) -> { object.remove(item[0]); sp.edit().putString("custom_typos", object.toString()).apply(); reloadTypoMapAsync(this); renderCustomTyposUI(); }).setNeutralButton("编辑", (d, w) -> { editingTypoKey = item[0]; original.setText(item[0]); corrected.setText(item[0].equals(item[1]) ? "" : item[1]); add.setText("完成"); }).setNegativeButton("取消", null).show());
                container.addView(view);
            }
            if (items.size() > 15) { expand.setVisibility(View.VISIBLE); expand.setText(isTyposExpanded ? "折叠" : "展开全部"); expand.setOnClickListener(v -> { isTyposExpanded = !isTyposExpanded; renderCustomTyposUI(); }); } else expand.setVisibility(View.GONE);
        } catch (Exception ignored) {}
    }

    private void renderHistoryUI() {
        LinearLayout container = findViewById(R.id.llHistory); if (container == null) return; container.removeAllViews();
        try {
            JSONArray records = new JSONArray(sp.getString("history_records", "[]"));
            for (int i = 0; i < records.length(); i++) {
                JSONObject record = records.getJSONObject(i); String time = record.optString("time", ""), preview = record.optString("preview", ""), fileId = record.optString("file", record.optString("fileName", ""));
                if (preview.isEmpty() && record.has("text")) { String raw = record.optString("text", ""); preview = raw.length() > 16 ? raw.substring(0, 16).replace("\n", " ") + "..." : raw.replace("\n", " "); }
                if (preview.length() > 16) preview = preview.substring(0, 16) + "...";
                LinearLayout item = new LinearLayout(this); item.setOrientation(LinearLayout.VERTICAL); item.setPadding(0, 24, 0, 24); item.setBackgroundResource(R.drawable.item_bg_selector); item.setClickable(true);
                TextView timeView = new TextView(this); timeView.setText(time); timeView.setTextSize(12f + Math.max(-3, Math.min(3, sp.getInt("font_offset_sys", 0)))); timeView.setTextColor(0xFF9E9E9E); TextView previewView = new TextView(this); previewView.setText(preview); previewView.setTextSize(14f + Math.max(-3, Math.min(3, sp.getInt("font_offset_sys", 0)))); item.addView(timeView); item.addView(previewView);
                item.setOnClickListener(v -> restoreHistory(record, fileId)); int index = i;
                item.setOnLongClickListener(v -> { new AlertDialog.Builder(this).setMessage("确认删除这条历史记录吗？").setPositiveButton("删除", (d, w) -> deleteHistoryRecord(records, index, fileId)).setNegativeButton("取消", null).show(); return true; });
                container.addView(item);
                if (i < records.length() - 1) { View line = new View(this); line.setLayoutParams(new LinearLayout.LayoutParams(-1, 1)); line.setBackgroundColor(0xFFE0E0E0); container.addView(line); }
            }
        } catch (Exception ignored) {}
    }

    private void restoreHistory(JSONObject record, String fileId) {
        final long restoreGeneration = ++historyRestoreGeneration;
        drawerLayout.closeDrawer(GravityCompat.END); progressBar.setVisibility(View.VISIBLE); progressBar.setIndeterminate(true);
        AppExecutors.IO.execute(() -> {
            File directory = new File(getFilesDir(), "history"); String full = fileId.isEmpty() ? record.optString("text", "") : HistoryStore.readUtf8(new File(directory, fileId + ".txt")); String blocks = fileId.isEmpty() ? "" : HistoryStore.readUtf8(new File(directory, fileId + "_blocks.json")); String manual = fileId.isEmpty() ? "" : HistoryStore.readUtf8(new File(directory, fileId + "_manual.json"));
            SpannableStringBuilder restored = manual.isEmpty() ? null : deserializeSpannable(manual);
            List<List<TextBlock>> restoredBlocks = blocks.isEmpty() ? null : deserializeBlocks(blocks);
            AppExecutors.MAIN.post(() -> {
                if (isFinishing() || isDestroyed() || restoreGeneration != historyRestoreGeneration) return;
                isRestoringHistory = true; inputText.setText(full); isRestoringHistory = false; lastSavedHistoryFileId = fileId;
                if (!manual.isEmpty()) {
                    if (restored != null) { isManuallyEditedOut = true; setResultStaleWarning(false); outputText.setText(restored); outputText.setMovementMethod(MyLinkMovementMethod.getInstance()); outputText.setHighlightColor(Color.TRANSPARENT); btnCheck.setText("继续纠错"); btnCopy.setEnabled(true); btnSaveTxt.setEnabled(true); }
                } else if (!blocks.isEmpty()) {
                    isManuallyEditedOut = false; allSentencesBlocks = restoredBlocks; lastTimeMs = Math.max(0L, record.optLong("elapsedMs", 0L)); showJumpHintForCurrentResult = false; pendingFreshJumpHintDecision = false; setResultStaleWarning(false); renderFinalBlocks(); btnCheck.setText("继续纠错"); btnCopy.setEnabled(true); btnSaveTxt.setEnabled(true);
                } else { isManuallyEditedOut = false; allSentencesBlocks.clear(); outputText.setText(""); setResultStaleWarning(false); btnCheck.setText("开始纠错"); }
                progressBar.setVisibility(View.INVISIBLE); progressBar.setIndeterminate(false);
            });
        });
    }

    private void deleteHistoryRecord(JSONArray records, int index, String fileId) {
        HistoryStore.deleteRecord(this, fileId);
        if (fileId.equals(lastSavedHistoryFileId)) { lastSavedHistoryFileId = null; isManuallyEditedOut = false; boolean old = isRestoringHistory; isRestoringHistory = true; inputText.setText(""); isRestoringHistory = old; allSentencesBlocks.clear(); outputText.setText(""); setResultStaleWarning(false); btnCheck.setText("开始纠错"); btnCopy.setEnabled(false); btnSaveTxt.setEnabled(false); Toast.makeText(this, "当前显示的历史记录已被删除", Toast.LENGTH_SHORT).show(); }
        records.remove(index); sp.edit().putString("history_records", records.toString()).apply(); renderHistoryUI();
    }

    @Override public void onBackPressed() {
        if (isInputEditorOpen && inputEditorOverlay != null && inputEditorOverlay.getVisibility() == View.VISIBLE) { confirmCloseInputEditor(); return; }
        if (isEditorOpen && expandedEditorOverlay != null
                && expandedEditorOverlay.getVisibility() == View.VISIBLE) {
            View closeButton = findViewById(R.id.btnEditorClose);
            if (closeButton != null) {
                closeButton.performClick();
                return;
            }
        }
        super.onBackPressed();
    }

    @Override protected void onSaveInstanceState(Bundle state) {
        flushInputSync(); saveSettings(currentIsFast);
        if (screenStateToken == null) screenStateToken = java.util.UUID.randomUUID().toString();
        boolean manualSnapshot = isEditorOpen || isManuallyEditedOut;
        CharSequence manualText = isEditorOpen ? expandedEditText.getText() : outputText.getText();
        try {
            EditText active = isInputEditorOpen ? expandedInputEditText : inputText;
            JSONObject snapshot = new JSONObject().put("token", screenStateToken).put("input", active.getText().toString())
                    .put("revision", DraftSync.read(sp).revision).put("selection", active.getSelectionStart())
                    .put("source", displayedResultInput == null ? JSONObject.NULL : displayedResultInput)
                    .put("stale", displayedResultStale).put("elapsed", lastTimeMs)
                    .put("file", lastSavedHistoryFileId == null ? "" : lastSavedHistoryFileId)
                    .put("manual", manualSnapshot && !isCheckingMain)
                    .put("blocks", isCheckingMain || manualSnapshot ? "" : serializeBlocks(allSentencesBlocks))
                    .put("manual_text", manualSnapshot && !isCheckingMain ? serializeSpannable(new SpannableString(manualText)) : "")
                    .put("message", isCheckingMain ? "纠错因界面重建中断，请重新开始。" : outputText.getText().toString())
                    .put("scroll", scrollView.getScrollY());
            ScreenStateStore.write(new File(getFilesDir(), "screen_state.json"), snapshot);
            state.putString("screen_state_token", screenStateToken);
        } catch (Exception error) { Toast.makeText(this, "界面状态保存失败：" + errorDetails(error), Toast.LENGTH_LONG).show(); }
        super.onSaveInstanceState(state);
    }

    @Override protected void onRestoreInstanceState(Bundle state) {
        boolean old = isRestoringHistory; isRestoringHistory = true;
        try { super.onRestoreInstanceState(state); } finally { isRestoringHistory = old; }
    }

    private void restoreScreenState(Bundle state) {
        screenStateToken = state == null ? java.util.UUID.randomUUID().toString() : state.getString("screen_state_token");
        DraftSync.Snapshot shared = DraftSync.read(sp);
        JSONObject snapshot = null;
        try {
            if (state != null && screenStateToken != null) snapshot = ScreenStateStore.read(new File(getFilesDir(), "screen_state.json"), screenStateToken);
            String text = ScreenStateStore.restoredInput(snapshot, shared.text, shared.revision);
            boolean old = isRestoringHistory; isRestoringHistory = true;
            try { inputText.setText(text); inputText.setSelection(Math.max(0, Math.min(text.length(), snapshot == null ? text.length() : snapshot.optInt("selection", text.length())))); }
            finally { isRestoringHistory = old; }
            DraftSync.publish(sp, text);
            if (snapshot == null) { allSentencesBlocks = new ArrayList<>(); return; }
            isManuallyEditedOut = snapshot.optBoolean("manual", false);
            String blocks = snapshot.optString("blocks", "");
            allSentencesBlocks = blocks.isEmpty() ? new ArrayList<>() : deserializeBlocks(blocks);
            lastTimeMs = snapshot.optLong("elapsed", 0L);
            lastSavedHistoryFileId = snapshot.optString("file", ""); if (lastSavedHistoryFileId.isEmpty()) lastSavedHistoryFileId = null;
            displayedResultInput = snapshot.isNull("source") ? null : snapshot.optString("source", null);
            if (isManuallyEditedOut) {
                outputText.setText(deserializeSpannable(snapshot.getString("manual_text")));
                outputText.setMovementMethod(MyLinkMovementMethod.getInstance()); outputText.setHighlightColor(Color.TRANSPARENT);
            } else if (!allSentencesBlocks.isEmpty()) renderFinalBlocks();
            else outputText.setText(snapshot.optString("message", ""));
            setResultStaleWarning(DraftSync.resultIsStale(text, displayedResultInput, hasDisplayedCorrectionResult()));
            btnCopy.setEnabled(hasDisplayedCorrectionResult()); btnCheck.setText(hasDisplayedCorrectionResult() ? "继续纠错" : "开始纠错");
            int scroll = snapshot.optInt("scroll", 0); scrollView.post(() -> scrollView.scrollTo(0, scroll));
        } catch (Exception error) { outputText.setText("界面状态恢复失败：" + errorDetails(error)); }
    }

    @Override protected void onPause() { flushInputSync(); saveSettings(currentIsFast); super.onPause(); }

    @Override protected void onDestroy() {
        inputSyncHandler.removeCallbacksAndMessages(null);
        isCheckingMain = false; inferenceGeneration++; importGeneration++; importing = false;
        if (instance == this) instance = null;
        isEditorOpen = false; isInputEditorOpen = false;
        super.onDestroy();
    }

    // Text from the floating window is a new document, not a manual edit of the
    // previous main-screen result. Never display the previous result alongside it.
    private void acceptExternalDraft(String text) {
        if (text == null || text.equals(inputText.getText().toString())) return;
        historyRestoreGeneration++;
        if (isCheckingMain) cancelMainCheck();
        allSentencesBlocks.clear();
        isManuallyEditedOut = false;
        lastEditorSpannable = null;
        currentClauseLinks.clear();
        lastSavedHistoryFileId = null;
        showJumpHintForCurrentResult = false;
        pendingFreshJumpHintDecision = false;
        setResultStaleWarning(false);
        outputText.setText("");
        btnCopy.setEnabled(false);
        btnCheck.setText("开始纠错");
        btnCheck.setEnabled(true);
        btnSaveTxt.setEnabled(!text.isEmpty());
        // Drop any deferred publish from before the external handoff.
        inputSyncHandler.removeCallbacksAndMessages(null);
        mainSyncDirty = false;
        boolean wasRestoring = isRestoringHistory;
        isRestoringHistory = true;
        applyingExternalDraft = true;
        try { inputText.setText(text); }
        finally { applyingExternalDraft = false; isRestoringHistory = wasRestoring; }
    }
    public void onFloatResultReady() {
        // An asynchronously completed float result can arrive while the activity is
        // visible. Accept it only for the exact current original text.
        if (!hasNewFloatResult || isCheckingMain || isEditorOpen || isInputEditorOpen
                || inputText == null || pendingFloatSourceText == null
                || !pendingFloatSourceText.equals(inputText.getText().toString())
                || !pendingFloatSourceText.equals(DraftSync.read(sp).text)) return;
        hasNewFloatResult = false; pendingFloatSourceText = null; isManuallyEditedOut = false; if (pendingFloatFileId != null) lastSavedHistoryFileId = pendingFloatFileId;
        allSentencesBlocks = new ArrayList<>(pendingFloatBlocks); lastTimeMs = pendingFloatTimeMs; pendingFloatBlocks = new ArrayList<>(); pendingFloatFileId = null;
        String sync = sp.getString("sync_text", ""); if (!sync.equals(inputText.getText().toString())) { boolean old = isRestoringHistory; isRestoringHistory = true; inputText.setText(sync); isRestoringHistory = old; }
        markFreshCorrectionResult(); setResultStaleWarning(false); renderFinalBlocks(); btnCopy.setEnabled(true); btnCheck.setEnabled(true); btnCheck.setText("继续纠错"); btnSaveTxt.setEnabled(true); scrollView.post(() -> scrollView.fullScroll(View.FOCUS_UP));
    }

    @Override protected void onResume() {
        super.onResume(); String sync = DraftSync.read(sp).text;
        if (!isInputEditorOpen && !isEditorOpen) acceptExternalDraft(sync);
        boolean fast = sp.getBoolean("is_fast_mode", false); if (fast != currentIsFast || rgMode.getCheckedRadioButtonId() == -1) { currentIsFast = fast; rgMode.check(fast ? R.id.rbFast : R.id.rbPro); loadSettings(fast); }
        if (hasNewFloatResult) onFloatResultReady();
    }

    @Override protected void onNewIntent(Intent intent) { super.onNewIntent(intent); setIntent(intent); handleIntent(intent); }

    private void handleIntent(Intent intent) {
        if (intent == null) return;
        if (Intent.ACTION_SEND.equals(intent.getAction()) && intent.getType() != null) {
            if ("text/plain".equals(intent.getType())) {
                String text = intent.getStringExtra(Intent.EXTRA_TEXT); if (text != null) checkAndPromptCleanup(this, text, cleaned -> { acceptExternalDraft(cleaned); DraftSync.publish(sp, cleaned); });
            } else if (intent.getType().startsWith("image/")) {
                android.net.Uri uri = intent.getParcelableExtra(Intent.EXTRA_STREAM); if (uri != null) importFiles(java.util.Collections.singletonList(uri));
            }
        } else if (intent.hasExtra("SYNC_TEXT")) {
            String text = intent.getStringExtra("SYNC_TEXT");
            if (text != null) { acceptExternalDraft(text); DraftSync.publish(sp, text); }
        }
        if (hasNewFloatResult) onFloatResultReady();
    }

    @Override protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode == 201) {
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M && android.provider.Settings.canDrawOverlays(this)) startFloatingService(); else Toast.makeText(this, "悬浮窗权限未被授予，无法开启", Toast.LENGTH_SHORT).show();
            return;
        }
        if (requestCode == 102 && resultCode == RESULT_OK && data != null) { importSelectedFiles(data); return; }
        if (requestCode == 101 && resultCode == RESULT_OK && data != null && data.getData() != null) saveSelectedDocument(data.getData());
    }

    private volatile long importGeneration;
    private boolean importing;

    private void cancelImport() {
        importGeneration++;
        if (importing) { importing = false; if (!isCheckingMain) progressBar.setVisibility(View.INVISIBLE); }
    }

    private void importSelectedFiles(Intent data) {
        List<android.net.Uri> uris = new ArrayList<>();
        if (data.getClipData() != null) { int count = data.getClipData().getItemCount(), limit = Math.min(count, 20); for (int i = 0; i < limit; i++) uris.add(data.getClipData().getItemAt(i).getUri()); if (count > 20) Toast.makeText(this, "最多支持选择20个文件，已截断前20个", Toast.LENGTH_SHORT).show(); }
        else if (data.getData() != null) uris.add(data.getData());
        importFiles(uris);
    }

    private void importFiles(List<android.net.Uri> uris) {
        if (uris.isEmpty()) return;
        if (isCheckingMain) cancelMainCheck();
        final long generation = ++importGeneration; importing = true;
        Context app = getApplicationContext();
        Toast.makeText(this, "正在处理导入文件，请稍候...", Toast.LENGTH_SHORT).show(); progressBar.setMax(100); progressBar.setVisibility(View.VISIBLE); progressBar.setProgress(0);
        AppExecutors.IO.execute(() -> {
            StringBuilder combined = new StringBuilder(); String failure = ""; int failed = 0;
            for (int i = 0; i < uris.size(); i++) {
                if (generation != importGeneration) return;
                int fileIndex = i; String text = extractTextFromUriSync(app, uris.get(i), new TextExtractCallback() {
                    @Override public void onStart() {}
                    @Override public void onProgress(int progress, int max) { int overall = fileIndex * 100 / uris.size() + progress * 100 / Math.max(1, max) / uris.size(); AppExecutors.MAIN.post(() -> { if (generation == importGeneration && !isDestroyed()) progressBar.setProgress(overall); }); }
                    @Override public void onExtracted(String text) {}
                });
                if (text != null && !text.trim().isEmpty()) {
                    if (combined.length() > 0) combined.append("\n\n---------------------------------\n\n");
                    combined.append(text);
                } else { failed++; failure = getLastExtractError(); }
            }
            String finalText = combined.toString(), detail = failure; int failedCount = failed; AppExecutors.MAIN.post(() -> {
                if (generation != importGeneration || isDestroyed() || isFinishing()) return;
                importing = false; progressBar.setVisibility(View.INVISIBLE);
                if (!finalText.trim().isEmpty()) checkAndPromptCleanup(this, finalText, cleaned -> { if (generation != importGeneration || isDestroyed() || isFinishing()) return; lastSavedHistoryFileId = null; inputText.setText(cleaned); DraftSync.publish(sp, cleaned); saveHistory(cleaned, null); Toast.makeText(this, failedCount == 0 ? "导入成功" : "已导入可读取的文件；另有" + failedCount + "个文件为空或读取失败", Toast.LENGTH_LONG).show(); });
                else { Toast.makeText(this, detail.isEmpty() ? "无法读取文件内容或未识别到文字" : "导入失败：" + detail, Toast.LENGTH_LONG).show(); }
            });
        });
    }

    private void saveSelectedDocument(android.net.Uri uri) {
        final int format = saveFormat; final String text = pendingSaveText;
        AppExecutors.IO.execute(() -> {
            boolean success = false;
            try (OutputStream output = getContentResolver().openOutputStream(uri)) {
                if (output == null) return;
                if (format == 0 || format == 1) output.write(text.getBytes(StandardCharsets.UTF_8));
                else if (format == 2) writePdf(output, text);
                else if (format == 3) writeDocx(output, text);
                else writeImage(output, text, format == 4);
                success = true;
            } catch (Exception ignored) {}
            boolean saved = success;
            AppExecutors.MAIN.post(() -> Toast.makeText(this, saved ? "保存成功" : "保存过程出现错误", Toast.LENGTH_SHORT).show());
        });
    }

    private void writePdf(OutputStream output, String text) throws Exception {
        android.graphics.pdf.PdfDocument document = new android.graphics.pdf.PdfDocument(); android.text.TextPaint paint = new android.text.TextPaint(android.graphics.Paint.ANTI_ALIAS_FLAG); paint.setTextSize(14); paint.setColor(Color.BLACK);
        int pageWidth = 595, pageHeight = 842, margin = 24, contentWidth = pageWidth - margin * 2, contentHeight = pageHeight - margin * 2;
        android.text.StaticLayout full = new android.text.StaticLayout(text, paint, contentWidth, Layout.Alignment.ALIGN_NORMAL, 1.5f, 0, false);
        int firstLine = 0, pageNumber = 1;
        while (firstLine < full.getLineCount()) {
            int lastLine = firstLine;
            while (lastLine + 1 < full.getLineCount() && full.getLineBottom(lastLine + 1) - full.getLineTop(firstLine) <= contentHeight) lastLine++;
            int start = full.getLineStart(firstLine), end = full.getLineEnd(lastLine); CharSequence pageText = text.subSequence(start, end);
            android.text.StaticLayout pageLayout = new android.text.StaticLayout(pageText, paint, contentWidth, Layout.Alignment.ALIGN_NORMAL, 1.5f, 0, false);
            android.graphics.pdf.PdfDocument.Page page = document.startPage(new android.graphics.pdf.PdfDocument.PageInfo.Builder(pageWidth, pageHeight, pageNumber++).create()); page.getCanvas().translate(margin, margin); pageLayout.draw(page.getCanvas()); document.finishPage(page); firstLine = lastLine + 1;
        }
        document.writeTo(output); document.close();
    }

    private void writeDocx(OutputStream output, String text) throws Exception {
        try (java.util.zip.ZipOutputStream zip = new java.util.zip.ZipOutputStream(output)) {
            zip.putNextEntry(new java.util.zip.ZipEntry("[Content_Types].xml")); zip.write("<?xml version=\"1.0\" encoding=\"UTF-8\"?><Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/></Types>".getBytes(StandardCharsets.UTF_8)); zip.closeEntry();
            zip.putNextEntry(new java.util.zip.ZipEntry("_rels/.rels")); zip.write("<?xml version=\"1.0\" encoding=\"UTF-8\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"word/document.xml\"/></Relationships>".getBytes(StandardCharsets.UTF_8)); zip.closeEntry();
            zip.putNextEntry(new java.util.zip.ZipEntry("word/document.xml")); String safe = text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;"); StringBuilder xml = new StringBuilder("<?xml version=\"1.0\" encoding=\"UTF-8\"?><w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:body>"); for (String paragraph : safe.split("\n", -1)) xml.append("<w:p><w:r><w:t xml:space=\"preserve\">").append(paragraph).append("</w:t></w:r></w:p>"); xml.append("</w:body></w:document>"); zip.write(xml.toString().getBytes(StandardCharsets.UTF_8)); zip.closeEntry();
        }
    }

    private void writeImage(OutputStream output, String text, boolean jpeg) {
        android.text.TextPaint paint = new android.text.TextPaint(android.graphics.Paint.ANTI_ALIAS_FLAG); paint.setTextSize(40); paint.setColor(Color.BLACK); String value = text.isEmpty() ? "无内容" : text;
        android.text.StaticLayout layout = new android.text.StaticLayout(value, paint, 1000, Layout.Alignment.ALIGN_NORMAL, 1.5f, 0, false); int height = Math.max(80, layout.getHeight() + 80);
        if (height > 30000) throw new IllegalArgumentException("文本过长，无法保存为单张图片，请改用 PDF 或 DOCX");
        Bitmap bitmap = Bitmap.createBitmap(1080, height, Bitmap.Config.ARGB_8888);
        try { android.graphics.Canvas canvas = new android.graphics.Canvas(bitmap); canvas.drawColor(Color.WHITE); canvas.translate(40, 40); layout.draw(canvas); bitmap.compress(jpeg ? Bitmap.CompressFormat.JPEG : Bitmap.CompressFormat.PNG, jpeg ? 90 : 100, output); }
        finally { bitmap.recycle(); }
    }

    private void cancelMainCheck() {
        isCheckingMain = false; inferenceGeneration++;
        getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        progressBar.setVisibility(View.INVISIBLE); btnCheck.setText("开始纠错"); btnCheck.setEnabled(true);
        allSentencesBlocks.clear(); isManuallyEditedOut = false; lastEditorSpannable = null; currentClauseLinks.clear(); setResultStaleWarning(false);
        outputText.setText("已取消纠错。"); btnCopy.setEnabled(false); btnSaveTxt.setEnabled(inputText.length() > 0);
    }

    private void doInference(boolean fastMode, float temperature) {
        cancelImport(); progressBar.setMax(100);
        String text = inputText.getText().toString(); if (text.isEmpty()) { isCheckingMain = false; btnCheck.setText("开始纠错"); return; }
        final long generation = ++inferenceGeneration;
        final String historyFileId = lastSavedHistoryFileId;
        final AtomicBoolean previewPending = new AtomicBoolean();
        btnCopy.setEnabled(false); btnSaveTxt.setEnabled(false);
        float thresholdDe = parseFloatSafe(editThreshDe1.getText().toString(), Float.NaN), thresholdDi = parseFloatSafe(editThreshDe2.getText().toString(), Float.NaN), thresholdDe3 = parseFloatSafe(editThreshDe3.getText().toString(), Float.NaN);
        float thresholdZuo=parseFloatSafe(editThreshZuo.getText().toString(),Float.NaN), thresholdZuo4=parseFloatSafe(editThreshZuo4.getText().toString(),Float.NaN);
        if (!fastMode) noteProCorrectionStart(this);
        AppExecutors.INFERENCE.execute(() -> {
            if (generation != inferenceGeneration || isDestroyed()) return;
            boolean proAcquired = false;
            try {
                AppExecutors.MAIN.post(() -> { if (generation != inferenceGeneration || isDestroyed()) return; getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON); progressBar.setVisibility(View.VISIBLE); progressBar.setProgress(0); });
                if (!fastMode) {
                    proAcquired = acquireProEngine(this);
                    if (!proAcquired) throw new IllegalStateException("专业 HCAM 模型加载失败：" + SecureAsset.lastErrorSummary());
                }
                StringBuilder liveErrors = new StringBuilder(), liveText = new StringBuilder(text.length() + 100); int[] processed = {0}, liveErrorCount = {0}, docIndex = {1}; boolean multiDocument = text.contains("---------------------------------"); boolean[] markerPending = {multiDocument};
                CorrectionCore.Result result = CorrectionCore.run(text, fastMode, temperature, thresholdDe, thresholdDi, thresholdDe3, thresholdZuo, thresholdZuo4, new CorrectionCore.Listener() {
                    @Override public boolean isCancelled() { return !isCheckingMain || generation != inferenceGeneration || isFinishing() || isDestroyed(); }
                    @Override public void onError(String message, boolean minimumDisplay) {}
                    @Override public void onProgress(int current, int total, List<List<TextBlock>> completed, int errors, long elapsed) {
                        while (processed[0] < completed.size()) {
                            List<TextBlock> sentence = completed.get(processed[0]++);
                            appendLiveErrors(sentence, liveErrors, liveErrorCount);
                            for (TextBlock block : sentence) {
                                if (markerPending[0] && docIndex[0] == 1) { liveText.append("<font color='#757575'>［文档").append(docIndex[0]++).append("］</font><br>"); markerPending[0] = false; }
                                appendLiveHtmlText(liveText, block.current);
                                if (block.current.contains("---------------------------------")) liveText.append("<br><font color='#757575'>［文档").append(docIndex[0]++).append("］</font><br>");
                            }
                        }
                        if (!previewPending.compareAndSet(false, true)) return;
                        StringBuilder htmlBuilder = new StringBuilder(liveErrors.length() + liveText.length() + 256).append("<b>正在纠错...</b><br>已耗时 ").append(String.format(Locale.getDefault(), "%.1f", elapsed / 1000.0)).append(" 秒<br>进度：").append(current).append(" / ").append(total).append("<br><br>");
                        if (liveErrors.length() > 0) htmlBuilder.append("<b><font color='#757575'>【纠错记录】：</font></b><br>").append(liveErrors);
                        String html = htmlBuilder.append("<br><b><font color='#757575'>【全文预览】：</font></b><br>").append(liveText).toString();
                        Spanned preview = Html.fromHtml(html, Html.FROM_HTML_MODE_COMPACT);
                        final int displayedErrors = liveErrorCount[0];
                        AppExecutors.MAIN.post(() -> {
                            previewPending.set(false);
                            if (!isCheckingMain || generation != inferenceGeneration || isFinishing() || isDestroyed()) return; progressBar.setMax(total); progressBar.setProgress(current); outputText.setText(preview);
                            if (autoScrollEnabled) scrollView.post(() -> { if (generation != inferenceGeneration || isDestroyed()) return; if (displayedErrors > 0) { Layout layout = outputText.getLayout(); int offset = outputText.getText().toString().indexOf("【纠错记录】："); if (layout != null && offset >= 0) scrollView.scrollTo(0, Math.max(0, layout.getLineTop(layout.getLineForOffset(offset)) - scrollView.getHeight() + 150)); } else scrollView.scrollTo(0, 0); });
                        });
                    }
                });
                if (result == null) {
                    AppExecutors.MAIN.post(() -> { if (generation != inferenceGeneration || isDestroyed()) return; outputText.setText("已取消纠错。"); btnCheck.setText("开始纠错"); btnCheck.setEnabled(true); progressBar.setVisibility(View.INVISIBLE); });
                    return;
                }
                if (generation != inferenceGeneration || isDestroyed()) return;
                HistoryStore.saveBlocks(this, historyFileId, result.blocks, result.elapsedMs);
                AppExecutors.MAIN.post(() -> { if (generation != inferenceGeneration || isDestroyed()) return; isCheckingMain = false; btnCheck.setText("继续纠错"); allSentencesBlocks = result.blocks; lastTimeMs = result.elapsedMs; markFreshCorrectionResult(); setResultStaleWarning(false); renderFinalBlocks(); btnCheck.setEnabled(true); btnCopy.setEnabled(true); btnSaveTxt.setEnabled(true); scrollView.post(() -> scrollView.fullScroll(View.FOCUS_UP)); });
            } catch (Throwable exception) {
                String message = errorDetails(exception); AppExecutors.MAIN.post(() -> { if (generation != inferenceGeneration || isDestroyed()) return; isCheckingMain = false; btnCheck.setText("开始纠错"); outputText.setText("推理运行中断: " + message); btnCheck.setEnabled(true); btnSaveTxt.setEnabled(true); });
            } finally {
                if (proAcquired) releaseProEngine();
                AppExecutors.MAIN.post(() -> { if (generation != inferenceGeneration || isDestroyed()) return; getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON); progressBar.setVisibility(View.INVISIBLE); });
            }
        });
    }

    private static boolean isActiveCorrection(TextBlock block) {
        if (block == null || !block.isMutable) return false;
        if (!block.current.equals(block.original)) return true;
        return !block.userModified && block.exp != null && !block.exp.isEmpty();
    }

    private void appendLiveErrors(List<TextBlock> sentence, StringBuilder html, int[] errorCount) {
        boolean hasError = false;
        for (TextBlock block : sentence) if (isActiveCorrection(block)) { hasError = true; break; }
        if (!hasError) return;
        for (List<TextBlock> group : buildErrorGroups(sentence)) {
            List<TextBlock> errors = new ArrayList<>(); for (TextBlock block : group) if (isActiveCorrection(block)) errors.add(block); if (errors.isEmpty()) continue;
            html.append("<font color='#2196F3'><b>["); for (int i = 0; i < errors.size(); i++) { html.append(errorCount[0] + i + 1); if (i < errors.size() - 1) html.append(','); } html.append("]</b></font> ");
            for (TextBlock block : group) {
                String original = escapeHtmlQuick(block.original), current = escapeHtmlQuick(block.current);
                if (isActiveCorrection(block)) {
                    errorCount[0]++; String note = block.type == 1 ? " (置信度:" + String.format(Locale.getDefault(), "%.2f", block.conf) + ")" : (block.type == 4 ? " (自定义)" : ""); String oldColor = block.type == 6 ? "#E53935" : "#9E9E9E";
                    if (block.current.equals(block.original)) html.append("<font color='#E53935'><b>").append(original).append("</b></font><font color='#9E9E9E'><small>").append(note).append("</small></font>");
                    else { html.append("<font color='").append(oldColor).append("'><s>").append(original).append("</s></font>");
                        if (!block.current.isEmpty()) html.append(" <font color='#E53935'><b>").append(current).append("</b></font><font color='#9E9E9E'><small>").append(note).append("</small></font>"); }
                } else html.append(original);
            }
            html.append("<br><br>");
        }
    }

    private List<List<TextBlock>> buildErrorGroups(List<TextBlock> sentence) {
        List<List<TextBlock>> clauses = new ArrayList<>(); List<TextBlock> clause = new ArrayList<>();
        for (TextBlock block : sentence) {
            if (block.isMutable) clause.add(block);
            else {
                String text = block.original; int start = 0;
                for (int i = 0; i < text.length(); i++) if (text.charAt(i) == '，' || text.charAt(i) == ',' || text.charAt(i) == '；' || text.charAt(i) == ';' || text.charAt(i) == '、' || text.charAt(i) == '\n') { String part = text.substring(start, i + 1); if (!part.isEmpty()) clause.add(new TextBlock(part, part, false, 0, 0)); clauses.add(clause); clause = new ArrayList<>(); start = i + 1; }
                if (start < text.length()) { String part = text.substring(start); clause.add(new TextBlock(part, part, false, 0, 0)); }
            }
        }
        if (!clause.isEmpty()) clauses.add(clause);
        List<List<TextBlock>> groups = new ArrayList<>(); List<TextBlock> current = new ArrayList<>();
        for (List<TextBlock> item : clauses) {
            boolean hasError = false; for (TextBlock block : item) if (isActiveCorrection(block)) { hasError = true; break; }
            if (hasError) current.addAll(item); else if (!current.isEmpty()) { groups.add(current); current = new ArrayList<>(); }
        }
        if (!current.isEmpty()) groups.add(current); return groups;
    }

    private void jumpToWhitelistFromCorrection() {
        editingTypoKey = null;
        Button add = findViewById(R.id.btnAddTypo);
        EditText original = findViewById(R.id.etOriginal), corrected = findViewById(R.id.etCorrected);
        TextView hint = findViewById(R.id.tvWhitelistJumpHint);
        if (add != null) add.setText("添加");
        if (original != null) { original.setText(""); original.setHint("白名单"); }
        if (corrected != null) corrected.setText("");
        if (hint != null) hint.setVisibility(View.VISIBLE);
        renderCustomTyposUI(); renderHistoryUI();
        drawerLayout.openDrawer(GravityCompat.END);
        if (original != null) {
            original.requestFocus();
            original.postDelayed(() -> original.setHint("原始文本"), 600);
            original.postDelayed(() -> original.setHint("白名单"), 1200);
            original.postDelayed(() -> original.setHint("原始文本"), 1800);
            original.postDelayed(() -> {
                if (!original.hasFocus()) original.requestFocus();
                android.view.inputmethod.InputMethodManager imm = (android.view.inputmethod.InputMethodManager) getSystemService(Context.INPUT_METHOD_SERVICE);
                if (imm != null) imm.showSoftInput(original, android.view.inputmethod.InputMethodManager.SHOW_IMPLICIT);
            }, 220);
        }
    }

    private AlertDialog buildEditChoiceDialog(TextBlock block, String[] options, int whitelistIndex, android.content.DialogInterface.OnClickListener listener) {
        AlertDialog dialog = new AlertDialog.Builder(this).setTitle("手动修改 (当前：" + block.current + ")").setItems(options, listener).create();
        dialog.setOnShowListener(ignored -> {
            android.widget.ListView list = dialog.getListView();
            if (list == null) return;
            list.post(() -> {
                int first = list.getFirstVisiblePosition();
                View row = list.getChildAt(whitelistIndex - first);
                if (row instanceof TextView) {
                    TextView text = (TextView) row;
                    text.setTextColor(0xFF9E9E9E);
                    text.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP, 12.5f);
                    text.setPaintFlags(text.getPaintFlags() | android.graphics.Paint.UNDERLINE_TEXT_FLAG);
                }
            });
        });
        return dialog;
    }

    private void showEditDialog(TextBlock block) {
        if (isManuallyEditedOut) { Toast.makeText(this, "文本已手动编辑，无法使用还原。请长按进入便签模式修改。", Toast.LENGTH_LONG).show(); return; }
        if (block.type == 1) {
            String[] choices = "做作".contains(block.original) ? new String[]{"做","作"} : new String[]{"的","地","得"};
            String[] options=Arrays.copyOf(choices,choices.length+2); options[choices.length]="还原为原字 ("+block.original+")"; options[choices.length+1]="错改？点击这里加入白名单";
            AlertDialog dialog = buildEditChoiceDialog(block, options, 4, (d, which) -> {
                if (which == choices.length+1) { jumpToWhitelistFromCorrection(); return; }
                String choice = which < choices.length ? choices[which] : block.original;
                block.userModified = !choice.equals(block.modelCorrected); block.current = choice; renderFinalBlocks(); HistoryStore.saveBlocks(this, lastSavedHistoryFileId, allSentencesBlocks);
            });
            dialog.show();
        } else {
            String[] options = {"采用修改 (" + block.modelCorrected + ")", "还原 (" + block.original + ")", "错改？点击这里加入白名单"};
            AlertDialog dialog = buildEditChoiceDialog(block, options, 2, (d, which) -> {
                if (which == 2) { jumpToWhitelistFromCorrection(); return; }
                if (which == 0) { block.current = block.modelCorrected; block.userModified = false; }
                else { block.current = block.original; block.userModified = true; }
                renderFinalBlocks(); HistoryStore.saveBlocks(this, lastSavedHistoryFileId, allSentencesBlocks);
            });
            dialog.show();
        }
    }

    private void markFreshCorrectionResult() {
        pendingFreshJumpHintDecision = true;
    }

    private void resolveJumpHintForFreshResult(int currentErrors) {
        if (!pendingFreshJumpHintDecision) return;
        pendingFreshJumpHintDecision = false;
        showJumpHintForCurrentResult = false;
        if (currentErrors <= 0) return;
        int shown = sp.getInt("jump_hint_shown_count", 0);
        if (shown < 10) {
            showJumpHintForCurrentResult = true;
            sp.edit().putInt("jump_hint_shown_count", shown + 1).apply();
        }
    }

    private void renderFinalBlocks() {
        currentClauseLinks.clear();
        int currentErrors = 0; for (List<TextBlock> sentence : allSentencesBlocks) for (TextBlock block : sentence) if (isActiveCorrection(block)) currentErrors++;
        resolveJumpHintForFreshResult(currentErrors);
        Map<TextBlock, Integer> relativeOffsets = new HashMap<>(); Map<TextBlock, TargetSpan> editorTargets = new HashMap<>();
        SpannableStringBuilder fullMain = new SpannableStringBuilder(), fullEditor = new SpannableStringBuilder();
        boolean multiDocument = false; outer: for (List<TextBlock> sentence : allSentencesBlocks) for (TextBlock block : sentence) if (block.current.contains("---------------------------------")) { multiDocument = true; break outer; }
        int documentIndex = 1; boolean pendingMarker = multiDocument;
        for (List<TextBlock> sentence : allSentencesBlocks) {
            for (TextBlock block : sentence) {
                if (pendingMarker && documentIndex == 1) { appendDocumentMarker(fullMain, documentIndex); appendDocumentMarker(fullEditor, documentIndex); documentIndex++; pendingMarker = false; }
                boolean error = isActiveCorrection(block);
                int mainStart = fullMain.length(); fullMain.append(block.current); int[] mainRange = normalizedRange(mainStart, fullMain.length());
                if (error) relativeOffsets.put(block, mainRange[0]);
                if (block.isMutable) fullMain.setSpan(createEditSpan(block), mainRange[0], mainRange[1], mainRange[2]);

                int editorStart = fullEditor.length(); fullEditor.append(block.current); int[] editorRange = normalizedRange(editorStart, fullEditor.length());
                if (block.isMutable) {
                    if (error) { TargetSpan target = new TargetSpan(block.current); editorTargets.put(block, target); fullEditor.setSpan(target, editorRange[0], editorRange[1], editorRange[2]); }
                    if (!block.current.equals(block.original)) fullEditor.setSpan(new WavyUnderlineSpan(0xFF4CAF50), editorRange[0], editorRange[1], editorRange[2]);
                }
                if (block.current.contains("---------------------------------")) { appendDocumentMarker(fullMain, documentIndex); appendDocumentMarker(fullEditor, documentIndex); documentIndex++; }
            }
        }

        SpannableStringBuilder main = new SpannableStringBuilder(), editor = new SpannableStringBuilder(); int[] baseOffset = {0};
        String elapsedText = lastTimeMs > 0L ? "耗时 " + String.format(Locale.getDefault(), "%.2f", lastTimeMs / 1000.0) + " 秒。" : "";
        if (currentErrors == 0) {
            String header = "未发现错误。" + (elapsedText.isEmpty() ? "" : " " + elapsedText) + "\n\n"; int start = main.length(); main.append(header); main.setSpan(new ForegroundColorSpan(0xFF4CAF50), start, main.length(), Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
        } else {
            String header = "共更正 " + currentErrors + " 处错误。" + (elapsedText.isEmpty() ? "" : " " + elapsedText) + (showJumpHintForCurrentResult ? "\n（点击序号可快速跳转）" : "") + "\n\n"; int start = main.length(); main.append(header); main.setSpan(new ForegroundColorSpan(0xFF757575), start, main.length(), Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
            appendSectionHeader(main, "【纠错清单：】\n"); appendSectionHeader(editor, "【纠错清单：】\n");
            int errorIndex = 0;
            for (List<TextBlock> sentence : allSentencesBlocks) {
                for (List<TextBlock> group : buildErrorGroups(sentence)) {
                    List<TextBlock> errors = new ArrayList<>(); for (TextBlock block : group) if (isActiveCorrection(block)) errors.add(block); if (errors.isEmpty()) continue;
                    int markerStart = main.length(); appendNumbers(main, errorIndex, errors.size());
                    JumpSpan jump = new JumpSpan() {
                        @Override public int getTargetOffset(Spanned text) { for (TextBlock block : group) { Integer offset = relativeOffsets.get(block); if (offset != null && isActiveCorrection(block)) return baseOffset[0] + offset; } return -1; }
                        @Override public void onClick(View view) { jumpAndFlash((TextView) view, getTargetOffset((Spanned) ((TextView) view).getText()), scrollView); }
                        @Override public void updateDrawState(TextPaint paint) { paint.setColor(0xFF2196F3); paint.setUnderlineText(true); paint.setTypeface(android.graphics.Typeface.create("sans-serif-medium", 0)); }
                    };
                    main.setSpan(jump, markerStart, main.length(), Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
                    for (TextBlock block : group) {
                        if (isActiveCorrection(block)) { appendCorrection(main, block, true); errorIndex++; }
                        else main.append(block.current);
                    }
                    main.append('\n');

                    ClauseLink link = new ClauseLink(); int editorMarkerStart = editor.length(); appendNumbers(editor, errorIndex - errors.size(), errors.size()); int editorMarkerEnd = editor.length(); ListMarkerSpan marker = new ListMarkerSpan(); link.listMarkerSpan = marker;
                    editor.setSpan(marker, editorMarkerStart, editorMarkerEnd, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE); editor.setSpan(new ForegroundColorSpan(0xFF2196F3), editorMarkerStart, editorMarkerEnd, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE); editor.setSpan(new android.text.style.TypefaceSpan("sans-serif-medium"), editorMarkerStart, editorMarkerEnd, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
                    JumpSpan editorJump = new JumpSpan() {
                        @Override public int getTargetOffset(Spanned text) {
                            if (link.isDead) return -1;
                            for (TargetSpan target : link.targetSpans) { int start = text.getSpanStart(target); if (start >= 0 && start <= text.length()) return start; }
                            return -1;
                        }
                        @Override public void onClick(View view) { TextView textView = (TextView) view; int target = getTargetOffset((Spanned) textView.getText()); if (target >= 0) jumpEditorToOffset(textView, target); }
                        @Override public void updateDrawState(TextPaint paint) { paint.setColor(0xFF2196F3); paint.setUnderlineText(true); paint.setTypeface(android.graphics.Typeface.create("sans-serif-medium", 0)); }
                    };
                    editor.setSpan(editorJump, editorMarkerStart, editorMarkerEnd, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
                    for (TextBlock block : group) {
                        if (isActiveCorrection(block)) appendCorrection(editor, block, false); else editor.append(block.current);
                    }
                    editor.append('\n');
                    for (TextBlock block : errors) { TargetSpan target = editorTargets.get(block); if (target != null) link.targetSpans.add(target); }
                    currentClauseLinks.add(link);
                }
            }
            int separatorStart = main.length(); main.append("\n---------------------------------\n\n"); main.setSpan(new ForegroundColorSpan(0xFF757575), separatorStart, main.length(), Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
            int editorSeparatorStart = editor.length(); editor.append("\n---------------------------------\n\n"); editor.setSpan(new ForegroundColorSpan(0xFF757575), editorSeparatorStart, editor.length(), Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
        }

        appendSectionHeader(main, currentErrors > 0 ? "【修正后的全文】\n" : "【原文】\n"); appendSectionHeader(editor, currentErrors > 0 ? "【修正后的全文】\n" : "【原文】\n");
        if (main.length() > 0) main.setSpan(new IgnoredInCopySpan(), 0, main.length(), Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
        if (editor.length() > 0) editor.setSpan(new IgnoredInCopySpan(), 0, editor.length(), Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
        baseOffset[0] = main.length(); main.append(fullMain); editor.append(fullEditor);
        for (ClauseLink link : currentClauseLinks) {
            link.targetOffset = -1;
            for (TargetSpan target : link.targetSpans) {
                int start = editor.getSpanStart(target);
                if (start >= 0) { link.targetOffset = start; break; }
            }
        }
        lastEditorSpannable = editor;
        outputText.setText(main); outputText.setMovementMethod(MyLinkMovementMethod.getInstance()); outputText.setHighlightColor(Color.TRANSPARENT);
    }

    private void appendDocumentMarker(SpannableStringBuilder builder, int index) {
        int start = builder.length(); builder.append("［文档").append(String.valueOf(index)).append("］\n"); builder.setSpan(new ForegroundColorSpan(0xFF757575), start, builder.length(), Spanned.SPAN_EXCLUSIVE_EXCLUSIVE); builder.setSpan(new IgnoredInCopySpan(), start, builder.length(), Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
    }

    private int[] normalizedRange(int start, int end) {
        if (start == end && start > 0) start--; return new int[]{start, end, start == end ? Spanned.SPAN_POINT_MARK : Spanned.SPAN_EXCLUSIVE_EXCLUSIVE};
    }

    private EditSpan createEditSpan(TextBlock block) {
        return new EditSpan() {
            @Override public void onClick(View view) { showEditDialog(block); }
            @Override public void updateDrawState(TextPaint paint) {
                paint.setUnderlineText(true);
                paint.setTypeface(android.graphics.Typeface.create("sans-serif", android.graphics.Typeface.NORMAL));
                if (isActiveCorrection(block)) paint.setColor(block.userModified && !block.current.equals(block.original) ? 0xFF4CAF50 : 0xFFE53935);
                else paint.setColor(0xFF2196F3);
            }
        };
    }

    private void appendSectionHeader(SpannableStringBuilder builder, String value) {
        int start = builder.length(); builder.append(value); builder.setSpan(new ForegroundColorSpan(0xFF757575), start, builder.length(), Spanned.SPAN_EXCLUSIVE_EXCLUSIVE); builder.setSpan(new android.text.style.TypefaceSpan("sans-serif-medium"), start, builder.length(), Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
    }

    private void appendNumbers(SpannableStringBuilder builder, int startIndex, int count) {
        builder.append('['); for (int i = 0; i < count; i++) { builder.append(String.valueOf(startIndex + i + 1)); if (i < count - 1) builder.append(','); } builder.append("] ");
    }

    private void appendCorrection(SpannableStringBuilder builder, TextBlock block, boolean clickable) {
        int newStart;
        if (block.current.equals(block.original)) { newStart = builder.length(); builder.append(block.original); }
        else {
            int oldStart = builder.length(); builder.append(block.original);
            if (block.type == 6) builder.setSpan(new ColoredStrikethroughSpan(0xFF9E9E9E, 0xFFE53935), oldStart, builder.length(), Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
            else { builder.setSpan(new StrikethroughSpan(), oldStart, builder.length(), Spanned.SPAN_EXCLUSIVE_EXCLUSIVE); builder.setSpan(new ForegroundColorSpan(0xFF9E9E9E), oldStart, builder.length(), Spanned.SPAN_EXCLUSIVE_EXCLUSIVE); }
            if (block.current.isEmpty()) newStart = oldStart;
            else { builder.append(' '); newStart = builder.length(); builder.append(block.current); }
        }
        int[] range = normalizedRange(newStart, builder.length());
        if (clickable) builder.setSpan(createEditSpan(block), range[0], range[1], range[2]);
        else { builder.setSpan(new ForegroundColorSpan(block.userModified && !block.current.equals(block.original) ? 0xFF4CAF50 : 0xFFE53935), range[0], range[1], range[2]); builder.setSpan(new android.text.style.TypefaceSpan("sans-serif-medium"), range[0], range[1], range[2]); }
        if (!block.current.isEmpty() && !block.userModified && block.type == 1) appendSmallNote(builder, "置信度: " + String.format(Locale.getDefault(), "%.2f", block.conf)); else if (!block.current.isEmpty() && !block.userModified && block.type == 4) appendSmallNote(builder, "自定义");
    }

    private void appendSmallNote(SpannableStringBuilder builder, String note) {
        int start = builder.length(); builder.append('(').append(note).append(')'); builder.setSpan(new ForegroundColorSpan(0xFF9E9E9E), start, builder.length(), Spanned.SPAN_EXCLUSIVE_EXCLUSIVE); builder.setSpan(new android.text.style.RelativeSizeSpan(.85f), start, builder.length(), Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
    }

}
DEDEDE_SOURCE_EOF

mkdir -p "app/src/main/java/com/app/dedede"
cat > "app/src/main/java/com/app/dedede/ModelEngine.java" <<'DEDEDE_SOURCE_EOF'
package com.app.dedede;
import org.pytorch.executorch.*;
import java.nio.*;
import java.util.Arrays;

public final class ModelEngine implements FiveCharInference.Engine {
    public static final String NAME="PTE INT8 PC", EXT=".pte";
    private final Module module;
    private ModelEngine(String path){module=Module.load(path,Module.LOAD_MODE_MMAP,4);}
    public static ModelEngine load(String path){return new ModelEngine(path);}
    // The byte[] Tensor overload is INT8, not BOOL. JNI reads these virtual methods.
    private static final class BoolTensor extends Tensor {
        private final ByteBuffer data;
        BoolTensor(boolean[] mask){super(new long[]{1,mask.length});data=ByteBuffer.allocateDirect(mask.length).order(ByteOrder.nativeOrder());for(boolean b:mask)data.put((byte)(b?1:0));data.rewind();}
        @Override public DType dtype(){return DType.BOOL;}
        @Override public Buffer getRawDataBuffer(){return data;}
    }
    @Override public float[] forward(long[] ids,boolean[] mask){
        if(ids.length!=mask.length)throw new IllegalArgumentException("输入与 mask 长度不同");
        EValue[] values=module.forward(EValue.from(Tensor.fromBlob(ids,new long[]{1,ids.length})),EValue.from(new BoolTensor(mask)));
        if(values==null||values.length!=1||values[0]==null)throw new IllegalStateException("PTE 输出数量异常");
        Tensor t=values[0].toTensor();if(!Arrays.equals(t.shape(),new long[]{1,ids.length,5}))throw new IllegalStateException("PTE 输出形状异常："+Arrays.toString(t.shape()));
        return t.getDataAsFloatArray();
    }
    @Override public void close(){module.close();}
}
DEDEDE_SOURCE_EOF

mkdir -p "app/src/main/java/com/app/dedede"
cat > "app/src/main/java/com/app/dedede/NativeSecurity.java" <<'DEDEDE_SOURCE_EOF'
package com.app.dedede;
final class NativeSecurity {
    static { System.loadLibrary("dedede"); }
    private NativeSecurity() {}
    static native byte[] deriveAssetKeyNative(byte[] javaPart, byte[] buildToken, byte[] salt, String assetName);
}
DEDEDE_SOURCE_EOF

mkdir -p "app/src/main/java/com/app/dedede"
cat > "app/src/main/java/com/app/dedede/RuleStrings.java" <<'DEDEDE_SOURCE_EOF'
package com.app.dedede;
import org.json.JSONArray;
final class RuleStrings {
    private static volatile String[] values;
    private static volatile boolean attempted;
    private RuleStrings() {}
    private static void ensureLoaded() {
        if (attempted) return;
        synchronized (RuleStrings.class) {
            if (attempted) return;
            try {
                String raw = SecureAsset.readUtf8(DededeApp.context(), "sys_rules.dat");
                if (raw.isEmpty()) return;
                JSONArray array = new JSONArray(raw);
                String[] loaded = new String[array.length()];
                for (int i = 0; i < loaded.length; i++) loaded[i] = array.getString(i);
                values = loaded;
            } catch (Throwable error) {
                SecureAsset.recordError("规则资源加载失败", error);
            } finally {
                // Publish completion only after values/error are visible to other threads.
                attempted = true;
            }
        }
    }
    static boolean ready() { ensureLoaded(); return values != null; }
    static String s(int index) {
        ensureLoaded();
        String[] local = values;
        if (local == null) throw new IllegalStateException("规则资源不可用：" + SecureAsset.lastErrorSummary());
        if (index < 0 || index >= local.length) throw new IndexOutOfBoundsException("规则索引异常");
        return local[index];
    }
}
DEDEDE_SOURCE_EOF

mkdir -p "app/src/main/java/com/app/dedede"
cat > "app/src/main/java/com/app/dedede/ScreenStateStore.java" <<'DEDEDE_SOURCE_EOF'
package com.app.dedede;

import java.io.*;
import java.nio.charset.StandardCharsets;
import org.json.JSONObject;

/** Keep large editor text out of the Activity's Binder state bundle. */
public final class ScreenStateStore {
    private ScreenStateStore() {}
    public static String restoredInput(JSONObject state, String shared, long revision) throws Exception {
        return state != null && revision <= state.optLong("revision", 0L) ? state.getString("input") : shared;
    }
    public static void write(File target, JSONObject state) throws Exception {
        File temporary = new File(target.getPath() + ".part");
        try {
            try (FileOutputStream stream = new FileOutputStream(temporary)) {
                stream.write(state.toString().getBytes(StandardCharsets.UTF_8));
                stream.getFD().sync();
            }
            if (!temporary.renameTo(target)) throw new IOException("无法保存界面恢复文件");
        } finally {
            if (temporary.exists() && !temporary.delete()) temporary.deleteOnExit();
        }
    }
    public static JSONObject read(File target, String token) throws Exception {
        if (!target.isFile()) return null;
        StringBuilder text = new StringBuilder();
        try (Reader reader = new InputStreamReader(new FileInputStream(target), StandardCharsets.UTF_8)) {
            char[] buffer = new char[8192]; int count;
            while ((count = reader.read(buffer)) != -1) text.append(buffer, 0, count);
        }
        JSONObject state = new JSONObject(text.toString());
        return token.equals(state.optString("token")) ? state : null;
    }
}
DEDEDE_SOURCE_EOF

mkdir -p "app/src/main/java/com/app/dedede"
cat > "app/src/main/java/com/app/dedede/SecureAsset.java" <<'DEDEDE_SOURCE_EOF'
package com.app.dedede;

import android.content.Context;
import android.content.res.AssetManager;
import java.io.ByteArrayOutputStream;
import java.io.BufferedInputStream;
import java.io.BufferedOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.util.Arrays;
import java.util.zip.GZIPInputStream;
import javax.crypto.AEADBadTagException;
import javax.crypto.Cipher;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.SecretKeySpec;

final class SecureAsset {
    private static final byte[] MAGIC = new byte[]{'D', 'D', 'A', '3'};
    private static final int VERSION = 1;
    private static final int TAG_SIZE = 16;
    private static final int IO_BUFFER = 64 * 1024;
    private static final int MAX_CHUNK = 4 * 1024 * 1024;
    private static volatile String lastError = "";
    private SecureAsset() {}

    static void recordError(String stage, Throwable error) {
        StringBuilder details=new StringBuilder();Throwable current=error;for(int i=0;current!=null&&i<6;i++,current=current.getCause()){if(i>0)details.append(" → ");details.append(current.getClass().getSimpleName()).append(": ").append(current.getMessage());}
        String detail=details.length()==0?"未知异常":details.toString();
        lastError = stage + "（" + detail + "）";
        if (error != null) error.printStackTrace();
    }

    static String lastErrorSummary() {
        String value = lastError;
        return value == null || value.isEmpty() ? "未获得详细错误" : value;
    }

    static String readUtf8(Context context, String assetName) {
        ByteArrayOutputStream output = new ByteArrayOutputStream(32 * 1024);
        try {
            decrypt(context, assetName, output);
            return output.toString("UTF-8");
        } catch (Throwable error) {
            recordError("读取 " + assetName + " 失败", error);
            return "";
        }
    }

    static boolean decryptToFile(Context context, String assetName, File target) {
        File temporary = new File(target.getAbsolutePath() + ".part");
        try (FileOutputStream file = new FileOutputStream(temporary);
             BufferedOutputStream output = new BufferedOutputStream(file, IO_BUFFER)) {
            decrypt(context, assetName, output); output.flush();
            file.getFD().sync();
        } catch (Throwable error) {
            recordError("解密 " + assetName + " 失败", error);
            temporary.delete();
            return false;
        }
        if (target.exists() && !target.delete()) { temporary.delete(); recordError("提交模型文件失败",new IOException("无法删除旧目标文件")); return false; }
        if (!temporary.renameTo(target)) { temporary.delete(); recordError("提交模型文件失败",new IOException("无法重命名临时文件")); return false; }
        return true;
    }

    private static void decrypt(Context context, String assetName, OutputStream plainOutput) throws IOException, GeneralSecurityException {
        try (InputStream input = new BufferedInputStream(context.getAssets().open(assetName, AssetManager.ACCESS_STREAMING), IO_BUFFER);
             AuthenticatedChunks chunks = new AuthenticatedChunks(input, assetName);
             GZIPInputStream gzip = new GZIPInputStream(chunks, IO_BUFFER)) {
            byte[] buffer = new byte[IO_BUFFER];
            try {
                int first = gzip.read(), second = gzip.read();
                if (first >= 0) {
                    if ((chunks.flags & 1) != 0 && first == 0x44 && second == 0x45) { plainOutput.write(0x50); plainOutput.write(0x4B); }
                    else { plainOutput.write(first); if (second >= 0) plainOutput.write(second); }
                }
                int count;
                while ((count = gzip.read(buffer)) != -1) plainOutput.write(buffer, 0, count);
                // GZIP may stop before the encrypted asset ends, or swallow a trailer IO error.
                // Drain to the authenticated EOF and rethrow any latched error before committing.
                while (chunks.read(buffer) != -1) {}
            } finally { Arrays.fill(buffer, (byte)0); }
        }
    }

    private static final class AuthenticatedChunks extends InputStream {
        final InputStream input;
        final int flags, chunkSize, chunkCount;
        final long totalLength;
        byte[] key, encrypted, plain, nonce, aad;
        Cipher cipher;
        SecretKeySpec keySpec;
        long verified;
        int index, offset, limit;
        boolean ended, closed;
        IOException failure;
        AuthenticatedChunks(InputStream input, String assetName) throws IOException, GeneralSecurityException {
            this.input = input;
            byte[] magic = new byte[4]; readFully(input, magic);
            if (!Arrays.equals(MAGIC, magic)) throw new GeneralSecurityException("资源格式错误");
            int version = input.read(); flags = input.read();
            if (version != VERSION || flags < 0 || (flags & ~1) != 0) throw new GeneralSecurityException("资源版本错误");
            byte[] salt = new byte[16], prefix = new byte[8]; readFully(input, salt); readFully(input, prefix);
            chunkSize = readInt(input); totalLength = readLong(input); chunkCount = readInt(input);
            if (chunkSize < 4096 || chunkSize > MAX_CHUNK || totalLength <= 0 || chunkCount <= 0
                    || 1L + (totalLength - 1L) / chunkSize != chunkCount) throw new GeneralSecurityException("资源分块头异常");
            byte[] javaPart = null, token = null;
            try {
                ByteArrayOutputStream header = new ByteArrayOutputStream(64);
                header.write(MAGIC); header.write(version); header.write(flags); header.write(salt); header.write(prefix);
                writeInt(header, chunkSize); writeLong(header, totalLength); writeInt(header, chunkCount);
                header.write(assetName.getBytes(StandardCharsets.UTF_8));
                aad = Arrays.copyOf(header.toByteArray(), header.size() + 8);
                nonce = Arrays.copyOf(prefix, 12);
                javaPart = GeneratedSecuritySeed.revealPart(); token = GeneratedSecuritySeed.buildToken();
                key = NativeSecurity.deriveAssetKeyNative(javaPart, token, salt, assetName);
                if (key == null || key.length != 32) throw new GeneralSecurityException("安全环境校验失败");
                keySpec = new SecretKeySpec(key, "AES"); cipher = Cipher.getInstance("AES/GCM/NoPadding");
                encrypted = new byte[chunkSize + TAG_SIZE]; plain = new byte[chunkSize];
            } catch (IOException | GeneralSecurityException | RuntimeException error) { wipe(); throw error; }
            finally {
                if (javaPart != null) Arrays.fill(javaPart, (byte)0); if (token != null) Arrays.fill(token, (byte)0);
                Arrays.fill(salt, (byte)0); Arrays.fill(prefix, (byte)0);
            }
        }
        private boolean nextChunk() throws IOException {
            if (failure != null) throw failure;
            try { return nextChunkChecked(); } catch (IOException error) { failure = error; throw error; }
        }
        private boolean nextChunkChecked() throws IOException {
            if (closed) throw new IOException("资源流已关闭");
            if (ended) return false;
            if (index == chunkCount) {
                if (verified != totalLength || input.read() != -1) throw new IOException("资源尾部异常");
                ended = true; return false;
            }
            int length = readInt(input), expected = (int)Math.min((long)chunkSize, totalLength - verified);
            if (length != expected || length <= 0) throw new IOException("资源块长度异常");
            readFully(input, encrypted, length + TAG_SIZE);
            putInt(nonce, 8, index); putInt(aad, aad.length - 8, index); putInt(aad, aad.length - 4, length);
            try {
                cipher.init(Cipher.DECRYPT_MODE, keySpec, new GCMParameterSpec(128, nonce)); cipher.updateAAD(aad);
                Arrays.fill(plain, (byte)0);
                int decoded = cipher.doFinal(encrypted, 0, length + TAG_SIZE, plain, 0);
                if (decoded != length) throw new IOException("资源块解密长度异常");
                offset = 0; limit = decoded; verified += decoded; index++; return true;
            } catch (GeneralSecurityException error) { throw new IOException("资源完整性验证失败", error); }
            finally { Arrays.fill(encrypted, (byte)0); }
        }
        @Override public int read() throws IOException {
            if (failure != null) throw failure;
            if (offset == limit && !nextChunk()) return -1;
            return plain[offset++] & 0xFF;
        }
        @Override public int read(byte[] out, int start, int length) throws IOException {
            if (out == null) throw new NullPointerException();
            if (start < 0 || length < 0 || start > out.length - length) throw new IndexOutOfBoundsException();
            if (length == 0) return 0;
            if (failure != null) throw failure;
            if (offset == limit && !nextChunk()) return -1;
            int count = Math.min(length, limit - offset); System.arraycopy(plain, offset, out, start, count); offset += count; return count;
        }
        @Override public int available() { return closed ? 0 : limit - offset; }
        private void wipe() {
            for (byte[] bytes : new byte[][]{key, encrypted, plain, nonce, aad}) if (bytes != null) Arrays.fill(bytes, (byte)0);
            cipher = null; keySpec = null;
        }
        @Override public void close() throws IOException { if (closed) return; closed = true; wipe(); input.close(); }
    }

    private static void readFully(InputStream input, byte[] output, int length) throws IOException {
        int offset = 0;
        while (offset < length) {
            int count = input.read(output, offset, length - offset);
            if (count < 0) throw new IOException("资源数据不完整");
            if (count > 0) offset += count;
        }
    }

    private static int readInt(InputStream input) throws IOException {
        byte[] bytes = new byte[4]; readFully(input, bytes);
        return ((bytes[0] & 0xFF) << 24) | ((bytes[1] & 0xFF) << 16) | ((bytes[2] & 0xFF) << 8) | (bytes[3] & 0xFF);
    }

    private static long readLong(InputStream input) throws IOException {
        byte[] bytes = new byte[8]; readFully(input, bytes);
        long value = 0; for (byte item : bytes) value = (value << 8) | (item & 0xFFL); return value;
    }

    private static void writeInt(OutputStream output, int value) throws IOException {
        output.write((value >>> 24) & 0xFF); output.write((value >>> 16) & 0xFF); output.write((value >>> 8) & 0xFF); output.write(value & 0xFF);
    }

    private static void writeLong(OutputStream output, long value) throws IOException {
        for (int shift = 56; shift >= 0; shift -= 8) output.write((int)(value >>> shift) & 0xFF);
    }

    private static void putInt(byte[] output, int offset, int value) {
        output[offset] = (byte)(value >>> 24); output[offset + 1] = (byte)(value >>> 16); output[offset + 2] = (byte)(value >>> 8); output[offset + 3] = (byte)value;
    }

    private static void readFully(InputStream input, byte[] output) throws IOException {
        int offset = 0;
        while (offset < output.length) {
            int count = input.read(output, offset, output.length - offset);
            if (count < 0) throw new IOException("资源数据不完整");
            if (count == 0) continue;
            offset += count;
        }
    }
}
DEDEDE_SOURCE_EOF

mkdir -p "app/src/main/java/com/app/dedede"
cat > "app/src/main/java/com/app/dedede/SymbolCleanActivity.java" <<'DEDEDE_SOURCE_EOF'
package com.app.dedede;
import android.app.Activity;
import android.app.AlertDialog;
import android.graphics.Color;
import android.graphics.drawable.ColorDrawable;
import android.os.Build;
import android.os.Bundle;
import android.provider.Settings;
import android.text.InputFilter;
import android.view.ContextThemeWrapper;
import android.view.Gravity;
import android.view.ViewGroup;
import android.view.WindowManager;
import android.widget.CheckBox;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.TextView;
import android.widget.Toast;
import java.util.LinkedHashSet;
import java.util.Set;

public class SymbolCleanActivity extends Activity {
    public static MainActivity.TextCleanCallback callback;

    @Override protected void onCreate(Bundle savedInstanceState) {
        overridePendingTransition(0, 0);
        super.onCreate(savedInstanceState);
        getWindow().setBackgroundDrawable(new ColorDrawable(Color.TRANSPARENT));
        String rawText = getIntent().getStringExtra("raw_text");
        if (rawText == null) rawText = "";
        boolean hasStar = getIntent().getBooleanExtra("star", false);
        boolean hasHash = getIntent().getBooleanExtra("hash", false);
        boolean hasDash = getIntent().getBooleanExtra("dash", false);

        LinearLayout layout = new LinearLayout(this);
        layout.setOrientation(LinearLayout.VERTICAL);
        layout.setPadding(35, 25, 35, 10);
        TextView title = new TextView(this);
        title.setText("提示：发现符号残留"); title.setTextSize(15f); title.setTextColor(0xFF000000); title.getPaint().setFakeBoldText(true); title.setPadding(0, 0, 0, 8);
        TextView message = new TextView(this);
        message.setText("注意到文本可能存在符号残留，是否清理？"); message.setTextSize(13f); message.setTextColor(0xFF333333); message.setPadding(0, 0, 0, 10);
        layout.addView(title); layout.addView(message);

        LinearLayout.LayoutParams cbParams = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        cbParams.setMargins(0, -10, 0, -10);
        CheckBox cbStar = createCheckBox("去掉所有 * 号", hasStar);
        CheckBox cbHash = createCheckBox("去掉所有 # 号", hasHash);
        CheckBox cbDash = createCheckBox("去掉所有 - 号", hasDash);
        layout.addView(cbStar, cbParams); layout.addView(cbHash, cbParams); layout.addView(cbDash, cbParams);

        TextView customTitle = new TextView(this);
        customTitle.setText("去掉自定义标点 (最多4种)："); customTitle.setPadding(5, 5, 0, 5); customTitle.setTextColor(0xFF555555); customTitle.setTextSize(12f);
        layout.addView(customTitle);
        LinearLayout customLayout = new LinearLayout(this); customLayout.setOrientation(LinearLayout.HORIZONTAL);
        EditText[] customs = new EditText[4];
        for (int i = 0; i < customs.length; i++) {
            EditText edit = new EditText(this);
            edit.setId(1001 + i); edit.setFilters(new InputFilter[]{new InputFilter.LengthFilter(1)}); edit.setGravity(Gravity.CENTER); edit.setTextSize(14f); edit.setPadding(0, 0, 0, 0); edit.setScaleX(0.70f); edit.setScaleY(0.70f);
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1); lp.setMargins(6, -10, 6, -10);
            edit.setLayoutParams(lp); customs[i] = edit; customLayout.addView(edit);
        }
        layout.addView(customLayout);

        String finalText = rawText;
        android.content.Context dialogContext = (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && Settings.canDrawOverlays(this))
                ? new ContextThemeWrapper(getApplicationContext(), android.R.style.Theme_Material_Light_Dialog_Alert)
                : new ContextThemeWrapper(this, android.R.style.Theme_Material_Light_Dialog_Alert);

        AlertDialog dialog = new AlertDialog.Builder(dialogContext)
                .setView(layout).setCancelable(false)
                .setPositiveButton("是 (清理)", (d, which) -> {
                    Set<String> symbols = new LinkedHashSet<>();
                    if (cbStar.isChecked()) symbols.add("*");
                    if (cbHash.isChecked()) symbols.add("#");
                    if (cbDash.isChecked()) symbols.add("-");
                    boolean duplicate = false;
                    for (EditText custom : customs) {
                        String value = custom.getText().toString();
                        if (!value.isEmpty() && !symbols.add(value)) duplicate = true;
                    }
                    if (duplicate) Toast.makeText(this, "提示：已勾选的符号无需重复输入", Toast.LENGTH_SHORT).show();
                    String result = finalText;
                    for (String symbol : symbols) {
                        result = result.replace(symbol, "");
                        if (">".equals(symbol)) result = result.replace("＞", "");
                        if ("<".equals(symbol)) result = result.replace("＜", "");
                    }
                    MainActivity.TextCleanCallback current = callback;
                    if (current != null) current.onCleaned(result);
                    d.dismiss();
                })
                .setNegativeButton("否 (不清理)", (d, which) -> {
                    MainActivity.TextCleanCallback current = callback;
                    if (current != null) current.onCleaned(finalText);
                    d.dismiss();
                }).create();

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            if (Settings.canDrawOverlays(this)) dialog.getWindow().setType(WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY);
        } else dialog.getWindow().setType(WindowManager.LayoutParams.TYPE_PHONE);
        dialog.getWindow().setBackgroundDrawable(new ColorDrawable(0xFFFFFFFF));
        dialog.setOnShowListener(d -> {
            dialog.getButton(AlertDialog.BUTTON_POSITIVE).setTextColor(0xFF4CAF50);
            dialog.getButton(AlertDialog.BUTTON_NEGATIVE).setTextColor(0xFF9E9E9E);
        });
        dialog.setOnDismissListener(d -> finish());
        dialog.show();
        WindowManager.LayoutParams lp = new WindowManager.LayoutParams();
        lp.copyFrom(dialog.getWindow().getAttributes());
        lp.width = (int) (getResources().getDisplayMetrics().widthPixels * 0.80f);
        dialog.getWindow().setAttributes(lp);
    }

    private CheckBox createCheckBox(String text, boolean checked) {
        CheckBox box = new CheckBox(this); box.setText(text); box.setChecked(checked); box.setTextSize(14f); box.setTextColor(0xFF333333); box.setScaleX(0.75f); box.setScaleY(0.75f); box.setPivotX(0); return box;
    }

    @Override public void finish() {
        callback = null;
        MainActivity.isCleanDialogOpen = false;
        super.finish();
        overridePendingTransition(0, 0);
    }
}
DEDEDE_SOURCE_EOF

mkdir -p "app/src/main/res/drawable"
cat > "app/src/main/res/drawable/circle_bg.xml" <<'DEDEDE_SOURCE_EOF'
<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="oval"><solid android:color="#2196F3"/></shape>
DEDEDE_SOURCE_EOF

mkdir -p "app/src/main/res/drawable"
cat > "app/src/main/res/drawable/circle_btn_bg.xml" <<'DEDEDE_SOURCE_EOF'
<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="oval"><solid android:color="#03A9F4"/></shape>
DEDEDE_SOURCE_EOF

mkdir -p "app/src/main/res/drawable"
cat > "app/src/main/res/drawable/bg_check_gradient.xml" <<'DEDEDE_SOURCE_EOF'
<?xml version="1.0" encoding="utf-8"?>
<ripple xmlns:android="http://schemas.android.com/apk/res/android" android:color="#22FFFFFF">
    <item>
        <inset android:insetLeft="4dp" android:insetRight="4dp" android:insetTop="6dp" android:insetBottom="6dp">
            <shape><corners android:radius="12dp"/><solid android:color="#2196F3"/></shape>
        </inset>
    </item>
</ripple>
DEDEDE_SOURCE_EOF

mkdir -p "app/src/main/res/drawable"
cat > "app/src/main/res/drawable/bg_temp_outline.xml" <<'DEDEDE_SOURCE_EOF'
<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android">
    <solid android:color="#06FFFFFF"/>
    <stroke android:width="1dp" android:color="#16000000"/>
    <corners android:radius="8dp"/>
</shape>
DEDEDE_SOURCE_EOF

mkdir -p "app/src/main/res/drawable"
cat > "app/src/main/res/drawable/ic_dedede_fg.xml" <<'DEDEDE_SOURCE_EOF'
<vector xmlns:android="http://schemas.android.com/apk/res/android" android:width="28dp" android:height="28dp" android:viewportWidth="24" android:viewportHeight="24">
    <path android:fillColor="#FFFFFF" android:strokeColor="#FFFFFF" android:strokeWidth="1.2" android:pathData="M9,16.17L4.83,12l-1.42,1.41L9,19 21,7l-1.41,-1.41z"/>
</vector>
DEDEDE_SOURCE_EOF

mkdir -p "app/src/main/res/drawable"
cat > "app/src/main/res/drawable/ic_skin_shirt.xml" <<'DEDEDE_SOURCE_EOF'
<vector xmlns:android="http://schemas.android.com/apk/res/android" android:width="24dp" android:height="24dp" android:viewportWidth="24" android:viewportHeight="24">
    <path android:fillColor="#2196F3" android:pathData="M6.7,3.4L9.7,2.3c0.45,0.9 1.15,1.35 2.3,1.35s1.85,-0.45 2.3,-1.35L17.3,3.4 20.3,5.5 18.15,9.65 16.9,9.0V21H7.1V9.0L5.85,9.65 3.7,5.5z"/>
</vector>
DEDEDE_SOURCE_EOF

mkdir -p "app/src/main/res/drawable"
cat > "app/src/main/res/drawable/ic_skin_shirt_gradient.xml" <<'DEDEDE_SOURCE_EOF'
<vector xmlns:android="http://schemas.android.com/apk/res/android" android:width="24dp" android:height="24dp" android:viewportWidth="24" android:viewportHeight="24">
    <path android:fillColor="#8FA89A" android:pathData="M6.7,3.4L9.7,2.3c0.45,0.9 1.15,1.35 2.3,1.35s1.85,-0.45 2.3,-1.35L17.3,3.4 20.3,5.5 18.15,9.65 16.9,9.0V21H7.1V9.0L5.85,9.65 3.7,5.5z"/>
</vector>
DEDEDE_SOURCE_EOF

mkdir -p "app/src/main/res/drawable"
cat > "app/src/main/res/drawable/item_bg_selector.xml" <<'DEDEDE_SOURCE_EOF'
<?xml version="1.0" encoding="utf-8"?>
<selector xmlns:android="http://schemas.android.com/apk/res/android" android:enterFadeDuration="100" android:exitFadeDuration="800">
    <item android:state_pressed="true"><shape><solid android:color="#26000000"/></shape></item>
    <item><shape><solid android:color="@android:color/transparent"/></shape></item>
</selector>
DEDEDE_SOURCE_EOF

mkdir -p "app/src/main/res/drawable"
cat > "app/src/main/res/drawable/scrollbar_thumb.xml" <<'DEDEDE_SOURCE_EOF'
<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android"><solid android:color="#B39E9E9E"/><corners android:radius="4dp"/><size android:width="8dp"/></shape>
DEDEDE_SOURCE_EOF

mkdir -p "app/src/main/res/layout"
cat > "app/src/main/res/layout/activity_main.xml" <<'DEDEDE_SOURCE_EOF'
<?xml version="1.0" encoding="utf-8"?>
<androidx.drawerlayout.widget.DrawerLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:id="@+id/drawerLayout" android:layout_width="match_parent" android:layout_height="match_parent" android:background="@color/bg_color">

    <FrameLayout android:id="@+id/mainContentFrame" android:layout_width="match_parent" android:layout_height="match_parent" android:background="@color/bg_color">
        <LinearLayout android:id="@+id/mainBody" android:layout_width="match_parent" android:layout_height="match_parent" android:orientation="vertical" android:paddingStart="14dp" android:paddingEnd="14dp" android:paddingTop="12dp" android:paddingBottom="14dp" android:background="@color/bg_color">
            <RelativeLayout android:layout_width="match_parent" android:layout_height="wrap_content" android:layout_marginBottom="7dp">
                <TextView android:id="@+id/tvTitle" android:layout_width="wrap_content" android:layout_height="wrap_content" android:text="纠错 Pro" android:textSize="20sp" android:textStyle="bold" android:textColor="@color/text_primary" android:layout_alignParentStart="true" android:layout_centerVertical="true" android:clickable="true" android:focusable="true"/>
                <LinearLayout android:layout_width="wrap_content" android:layout_height="wrap_content" android:orientation="horizontal" android:layout_alignParentEnd="true" android:layout_centerVertical="true" android:gravity="center_vertical">
                    <androidx.appcompat.widget.AppCompatButton android:id="@+id/btnFloat" android:layout_width="24dp" android:layout_height="24dp" android:layout_marginEnd="8dp" android:text="✓" android:textSize="12sp" android:background="@drawable/circle_btn_bg" android:textColor="#FFFFFF" android:stateListAnimator="@null" android:padding="0dp"/>
                    <Button android:id="@+id/btnFont" android:layout_width="34dp" android:layout_height="34dp" android:text="A" android:textStyle="bold" android:textSize="19sp" android:background="@null" android:textColor="#2196F3" android:padding="0dp" android:insetTop="0dp" android:insetBottom="0dp"/>
                    <Button android:id="@+id/btnMenu" android:layout_width="32dp" android:layout_height="32dp" android:text="≡" android:textSize="14sp" android:backgroundTint="#BDBDBD" android:padding="0dp" android:insetTop="0dp" android:insetBottom="0dp" android:layout_marginStart="8dp"/>
                </LinearLayout>
            </RelativeLayout>

            <LinearLayout android:id="@+id/modeBar" android:layout_width="match_parent" android:layout_height="wrap_content" android:orientation="horizontal" android:gravity="center_vertical" android:layout_marginBottom="5dp">
                <RadioGroup android:id="@+id/rgMode" android:layout_width="0dp" android:layout_weight="1" android:layout_height="wrap_content" android:orientation="horizontal" android:gravity="center_vertical">
                    <RadioButton android:id="@+id/rbFast" android:layout_width="0dp" android:layout_height="48dp" android:layout_weight="1" android:minWidth="0dp" android:paddingStart="0dp" android:paddingEnd="0dp" android:text="极速" android:textColor="@color/text_primary" android:textSize="14sp"/>
                    <RadioButton android:id="@+id/rbPro" android:layout_width="0dp" android:layout_height="48dp" android:layout_weight="1.8" android:layout_marginStart="12dp" android:minWidth="0dp" android:paddingStart="0dp" android:paddingEnd="0dp" android:text="专业（HCAM）" android:checked="true" android:textColor="@color/text_primary" android:textSize="14sp"/>
                </RadioGroup>
                <LinearLayout android:id="@+id/paramTemp" android:layout_width="wrap_content" android:layout_height="36dp" android:orientation="horizontal" android:gravity="center_vertical" android:layout_marginStart="4dp" android:layout_marginEnd="4dp" android:paddingStart="6dp" android:paddingEnd="2dp" android:background="@drawable/bg_temp_outline">
                    <TextView android:id="@+id/labelTemp" android:layout_width="wrap_content" android:layout_height="wrap_content" android:text="温度" android:textSize="12.5sp" android:textColor="@color/text_secondary"/>
                    <EditText android:id="@+id/editTemp" android:layout_width="42dp" android:layout_height="34dp" android:minWidth="0dp" android:padding="0dp" android:text="1.0" android:contentDescription="温度" android:textColor="@color/text_primary" android:textSize="13sp" android:inputType="numberDecimal" android:maxLength="5" android:singleLine="true" android:gravity="center" android:background="@null"/>
                </LinearLayout>
            </LinearLayout>

            <TextView android:id="@+id/tvThresholdHint" android:layout_width="wrap_content" android:layout_height="wrap_content" android:layout_marginStart="6dp" android:layout_marginBottom="2dp" android:text="修改阈值" android:textSize="10sp" android:textColor="@color/text_secondary"/>
            <LinearLayout android:id="@+id/paramsCard" android:layout_width="match_parent" android:layout_height="wrap_content" android:orientation="vertical" android:background="@color/card_bg" android:paddingStart="6dp" android:paddingEnd="6dp" android:paddingTop="3dp" android:paddingBottom="4dp" android:layout_marginBottom="9dp">
                <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content" android:orientation="horizontal" android:gravity="center_vertical" android:baselineAligned="false">
                <LinearLayout android:id="@+id/paramDe" android:layout_width="0dp" android:layout_height="42dp" android:layout_weight="1" android:orientation="horizontal" android:gravity="center_vertical">
                    <TextView android:id="@+id/labelDe" android:layout_width="wrap_content" android:layout_height="wrap_content" android:text="的" android:textSize="15sp" android:textStyle="bold" android:textColor="@color/text_primary"/>
                    <EditText android:id="@+id/editThreshDe1" android:layout_width="0dp" android:layout_weight="1" android:layout_height="42dp" android:minWidth="0dp" android:padding="0dp" android:text="0.7" android:contentDescription="的字阈值" android:textColor="@color/text_primary" android:textSize="13sp" android:inputType="numberDecimal" android:maxLength="5" android:singleLine="true" android:gravity="center" android:background="@null"/>
                </LinearLayout>
                <LinearLayout android:id="@+id/paramDi" android:layout_width="0dp" android:layout_height="42dp" android:layout_weight="1" android:orientation="horizontal" android:gravity="center_vertical">
                    <TextView android:id="@+id/labelDi" android:layout_width="wrap_content" android:layout_height="wrap_content" android:text="地" android:textSize="15sp" android:textStyle="bold" android:textColor="@color/text_primary"/>
                    <EditText android:id="@+id/editThreshDe2" android:layout_width="0dp" android:layout_weight="1" android:layout_height="42dp" android:minWidth="0dp" android:padding="0dp" android:text="0.7" android:contentDescription="地字阈值" android:textColor="@color/text_primary" android:textSize="13sp" android:inputType="numberDecimal" android:maxLength="5" android:singleLine="true" android:gravity="center" android:background="@null"/>
                </LinearLayout>
                <LinearLayout android:id="@+id/paramDe3" android:layout_width="0dp" android:layout_height="42dp" android:layout_weight="1" android:orientation="horizontal" android:gravity="center_vertical">
                    <TextView android:id="@+id/labelDe3" android:layout_width="wrap_content" android:layout_height="wrap_content" android:text="得" android:textSize="15sp" android:textStyle="bold" android:textColor="@color/text_primary"/>
                    <EditText android:id="@+id/editThreshDe3" android:layout_width="0dp" android:layout_weight="1" android:layout_height="42dp" android:minWidth="0dp" android:padding="0dp" android:text="0.75" android:contentDescription="得字阈值" android:textColor="@color/text_primary" android:textSize="13sp" android:inputType="numberDecimal" android:maxLength="5" android:singleLine="true" android:gravity="center" android:background="@null"/>
                </LinearLayout>
                <LinearLayout android:id="@+id/paramZuo4" android:layout_width="0dp" android:layout_height="42dp" android:layout_weight="1" android:orientation="horizontal" android:gravity="center_vertical">
                    <TextView android:id="@+id/labelZuo4" android:layout_width="wrap_content" android:layout_height="wrap_content" android:text="作" android:textSize="15sp" android:textStyle="bold" android:textColor="@color/text_primary"/>
                    <EditText android:id="@+id/editThreshZuo4" android:layout_width="0dp" android:layout_weight="1" android:layout_height="42dp" android:minWidth="0dp" android:padding="0dp" android:text="0.75" android:contentDescription="作字阈值" android:textColor="@color/text_primary" android:textSize="13sp" android:inputType="numberDecimal" android:maxLength="5" android:singleLine="true" android:gravity="center" android:background="@null"/>
                </LinearLayout>
                <LinearLayout android:id="@+id/paramZuo" android:layout_width="0dp" android:layout_height="42dp" android:layout_weight="1" android:orientation="horizontal" android:gravity="center_vertical">
                    <TextView android:id="@+id/labelZuo" android:layout_width="wrap_content" android:layout_height="wrap_content" android:text="做" android:textSize="15sp" android:textStyle="bold" android:textColor="@color/text_primary"/>
                    <EditText android:id="@+id/editThreshZuo" android:layout_width="0dp" android:layout_weight="1" android:layout_height="42dp" android:minWidth="0dp" android:padding="0dp" android:text="0.75" android:contentDescription="做字阈值" android:textColor="@color/text_primary" android:textSize="13sp" android:inputType="numberDecimal" android:maxLength="5" android:singleLine="true" android:gravity="center" android:background="@null"/>
                </LinearLayout>
                </LinearLayout>
            </LinearLayout>

            <RelativeLayout android:layout_width="match_parent" android:layout_height="142dp" android:layout_marginBottom="10dp">
                <EditText android:id="@+id/inputText" android:layout_width="match_parent" android:layout_height="match_parent" android:hint="输入或粘贴文本..." android:textColorHint="@color/text_secondary" android:textColor="@color/text_primary" android:gravity="top|start" android:background="@color/card_bg" android:padding="12dp" android:paddingEnd="42dp" android:paddingBottom="24dp" android:textSize="15sp" android:scrollbars="vertical"/>
                <Button android:id="@+id/btnInputExpand" android:layout_width="32dp" android:layout_height="32dp" android:layout_alignParentTop="true" android:layout_alignParentEnd="true" android:layout_marginTop="0dp" android:layout_marginEnd="0dp" android:translationX="2dp" android:translationY="-2dp" android:text="⛶" android:textSize="16sp" android:textColor="#7B8CA4" android:background="?android:attr/selectableItemBackgroundBorderless" android:padding="0dp" android:insetTop="0dp" android:insetBottom="0dp" android:contentDescription="展开输入框"/>
                <TextView android:id="@+id/tvWordCount" android:layout_width="wrap_content" android:layout_height="wrap_content" android:layout_alignParentBottom="true" android:layout_alignParentEnd="true" android:layout_marginEnd="8dp" android:layout_marginBottom="3dp" android:text="0 字" android:textColor="#9E9E9E" android:textSize="11sp"/>
            </RelativeLayout>

            <Button android:id="@+id/btnCheck" android:layout_width="match_parent" android:layout_height="52dp" android:text="开始纠错" android:textSize="16sp" android:letterSpacing="0.075" android:textColor="#ECF5FF" android:layout_marginTop="2dp" android:layout_marginBottom="6dp" android:background="@drawable/bg_check_gradient" android:backgroundTint="@null"/>
            <ProgressBar android:id="@+id/progressBar" style="?android:attr/progressBarStyleHorizontal" android:layout_width="match_parent" android:layout_height="4dp" android:progressTint="#81C784" android:max="100" android:progress="0" android:layout_marginTop="-4dp" android:layout_marginBottom="4dp" android:visibility="invisible"/>

            <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content" android:orientation="horizontal" android:layout_marginBottom="10dp">
                <Button android:id="@+id/btnImport" android:layout_width="0dp" android:layout_height="48dp" android:layout_weight="1" android:text="导入" android:textSize="13sp" android:backgroundTint="@color/btn_light_green_bg" android:textColor="@color/btn_light_green_text" android:layout_marginRight="4dp"/>
                <Button android:id="@+id/btnPaste" android:layout_width="0dp" android:layout_height="48dp" android:layout_weight="1" android:text="粘贴" android:textSize="13sp" android:backgroundTint="@color/btn_light_green_bg" android:textColor="@color/btn_light_green_text" android:layout_marginRight="4dp"/>
                <Button android:id="@+id/btnClear" android:layout_width="0dp" android:layout_height="48dp" android:layout_weight="1" android:text="清空" android:textSize="13sp" android:backgroundTint="@color/btn_light_green_bg" android:textColor="@color/btn_light_green_text" android:layout_marginRight="4dp"/>
                <Button android:id="@+id/btnCopy" android:layout_width="0dp" android:layout_height="48dp" android:layout_weight="1" android:text="复制" android:textSize="13sp" android:backgroundTint="@color/btn_light_green_bg" android:textColor="@color/btn_light_green_text" android:layout_marginRight="4dp" android:enabled="false"/>
                <Button android:id="@+id/btnSaveTxt" android:layout_width="0dp" android:layout_height="48dp" android:layout_weight="1" android:text="保存" android:textSize="13sp" android:backgroundTint="@color/btn_light_green_bg" android:textColor="@color/btn_light_green_text"/>
            </LinearLayout>
            <TextView android:id="@+id/tvResultStaleWarning" android:layout_width="match_parent" android:layout_height="wrap_content" android:text="已修改原始文本，以下纠错结果对应修改前的内容，建议重新纠错。" android:textColor="#D32F2F" android:textSize="13sp" android:textStyle="bold" android:paddingLeft="8dp" android:paddingRight="8dp" android:paddingBottom="8dp" android:visibility="gone"/>

            <FrameLayout android:layout_width="match_parent" android:layout_height="match_parent">
                <ScrollView android:id="@+id/scrollView" android:layout_width="match_parent" android:layout_height="match_parent" android:scrollbarSize="16dp" android:scrollbarThumbVertical="@drawable/scrollbar_thumb" android:fadeScrollbars="false">
                    <TextView android:id="@+id/outputText" android:layout_width="match_parent" android:layout_height="wrap_content" android:textSize="15.5sp" android:background="@color/card_bg" android:padding="12dp" android:paddingEnd="30dp" android:textColor="@color/text_primary" android:lineSpacingExtra="5dp"/>
                </ScrollView>
                <View android:id="@+id/scrollTouchArea" android:layout_width="40dp" android:layout_height="match_parent" android:layout_gravity="end"/>
            </FrameLayout>
        </LinearLayout>

        <FrameLayout android:id="@+id/inputEditorOverlay" android:layout_width="match_parent" android:layout_height="match_parent" android:background="@color/bg_color" android:visibility="gone" android:clickable="true" android:focusable="true" android:elevation="11dp">
            <LinearLayout android:layout_width="match_parent" android:layout_height="match_parent" android:orientation="vertical">
                <LinearLayout android:id="@+id/inputEditorToolbar" android:layout_width="match_parent" android:layout_height="50dp" android:orientation="horizontal" android:gravity="center_vertical" android:background="@color/card_bg" android:elevation="4dp" android:paddingEnd="4dp">
                    <Button android:id="@+id/btnInputEditorCollapse" android:layout_width="0dp" android:layout_height="0dp" android:visibility="gone" android:text="↓" android:background="@null" android:focusable="false" android:padding="0dp"/>
                    <TextView android:id="@+id/tvInputEditorWordCount" android:layout_width="0dp" android:layout_height="wrap_content" android:layout_weight="1" android:layout_marginStart="18dp" android:text="0 ｜ 0 字" android:textColor="#8A8A8A" android:textSize="15sp" android:textStyle="bold"/>
                    <Button android:id="@+id/btnInputEditorIndent" android:layout_width="wrap_content" android:layout_height="wrap_content" android:minWidth="52dp" android:minHeight="38dp" android:paddingHorizontal="8dp" android:layout_marginEnd="3dp" android:text="缩进" android:textColor="#FFFFFF" android:textSize="13sp" android:backgroundTint="#2196F3"/>
                    <Button android:id="@+id/btnInputEditorUndo" android:layout_width="wrap_content" android:layout_height="wrap_content" android:minWidth="48dp" android:minHeight="38dp" android:paddingHorizontal="7dp" android:layout_marginEnd="3dp" android:text="撤销" android:textColor="#FFFFFF" android:textSize="13sp" android:backgroundTint="#2196F3"/>
                    <Button android:id="@+id/btnInputEditorRedo" android:layout_width="wrap_content" android:layout_height="wrap_content" android:minWidth="48dp" android:minHeight="38dp" android:paddingHorizontal="7dp" android:layout_marginEnd="3dp" android:text="还原" android:textColor="#FFFFFF" android:textSize="13sp" android:backgroundTint="#2196F3"/>
                    <Button android:id="@+id/btnInputEditorDone" android:layout_width="wrap_content" android:layout_height="wrap_content" android:minWidth="50dp" android:minHeight="38dp" android:paddingHorizontal="8dp" android:layout_marginEnd="6dp" android:text="完成" android:textColor="#FFFFFF" android:textSize="13sp" android:backgroundTint="#4CAF50"/>
                </LinearLayout>
                <FrameLayout android:layout_width="match_parent" android:layout_height="match_parent">
                    <EditText android:id="@+id/expandedInputEditText" android:layout_width="match_parent" android:layout_height="match_parent" android:hint="输入或粘贴文本..." android:textColorHint="@color/text_secondary" android:textColor="@color/text_primary" android:gravity="top|start" android:background="@null" android:padding="16dp" android:paddingEnd="36dp" android:paddingBottom="30dp" android:textSize="15sp" android:lineSpacingExtra="4dp" android:scrollbars="vertical"/>
                    <View android:id="@+id/inputEditorScrollTouchArea" android:layout_width="40dp" android:layout_height="match_parent" android:layout_gravity="end" android:layout_marginTop="52dp"/>
                </FrameLayout>
            </LinearLayout>
        </FrameLayout>

        <FrameLayout android:id="@+id/expandedEditorOverlay" android:layout_width="match_parent" android:layout_height="match_parent" android:background="@color/bg_color" android:visibility="gone" android:clickable="true" android:focusable="true" android:elevation="10dp">
            <LinearLayout android:layout_width="match_parent" android:layout_height="match_parent" android:orientation="vertical">
                <LinearLayout android:id="@+id/outputEditorToolbar" android:layout_width="match_parent" android:layout_height="50dp" android:orientation="horizontal" android:gravity="center_vertical" android:background="@color/card_bg" android:elevation="4dp">
                    <Button android:id="@+id/btnEditorCollapse" android:layout_width="50dp" android:layout_height="50dp" android:text="↓" android:textColor="#03A9F4" android:textSize="21sp" android:background="?android:attr/selectableItemBackgroundBorderless" android:textStyle="bold" android:focusable="false" android:padding="0dp"/>
                    <Space android:layout_width="0dp" android:layout_height="wrap_content" android:layout_weight="1"/>
                    <Button android:id="@+id/btnEditorIndent" android:layout_width="wrap_content" android:layout_height="wrap_content" android:minWidth="52dp" android:minHeight="38dp" android:paddingHorizontal="9dp" android:layout_marginEnd="4dp" android:text="首行缩进" android:textColor="#FFFFFF" android:textSize="13.5sp" android:backgroundTint="#2196F3"/>
                    <Button android:id="@+id/btnEditorUndo" android:layout_width="wrap_content" android:layout_height="wrap_content" android:minWidth="52dp" android:minHeight="38dp" android:paddingHorizontal="9dp" android:layout_marginEnd="4dp" android:text="撤销" android:textColor="#FFFFFF" android:textSize="13.5sp" android:backgroundTint="#2196F3"/>
                    <Button android:id="@+id/btnEditorRedo" android:layout_width="wrap_content" android:layout_height="wrap_content" android:minWidth="52dp" android:minHeight="38dp" android:paddingHorizontal="9dp" android:layout_marginEnd="4dp" android:text="还原" android:textColor="#FFFFFF" android:textSize="13.5sp" android:backgroundTint="#2196F3"/>
                    <Button android:id="@+id/btnEditorSave" android:layout_width="wrap_content" android:layout_height="wrap_content" android:minWidth="52dp" android:minHeight="38dp" android:paddingHorizontal="9dp" android:layout_marginEnd="8dp" android:text="保存" android:textColor="#FFFFFF" android:textSize="13.5sp" android:backgroundTint="#4CAF50"/>
                    <Button android:id="@+id/btnEditorClose" android:layout_width="50dp" android:layout_height="50dp" android:text="✕" android:textColor="#E53935" android:textSize="17sp" android:background="?android:attr/selectableItemBackgroundBorderless" android:focusable="false" android:padding="0dp"/>
                </LinearLayout>
                <ScrollView android:id="@+id/editorScrollView" android:layout_width="match_parent" android:layout_height="match_parent" android:fillViewport="true" android:scrollbarSize="16dp" android:scrollbarThumbVertical="@drawable/scrollbar_thumb" android:fadeScrollbars="false">
                    <EditText android:id="@+id/expandedEditText" android:layout_width="match_parent" android:layout_height="wrap_content" android:padding="16dp" android:paddingEnd="36dp" android:gravity="top|start" android:background="@null" android:textSize="15sp" android:textColor="@color/text_primary" android:lineSpacingExtra="5dp"/>
                </ScrollView>
            </LinearLayout>
            <View android:id="@+id/editorScrollTouchArea" android:layout_width="40dp" android:layout_height="match_parent" android:layout_gravity="end" android:layout_marginTop="52dp"/>
        </FrameLayout>
    </FrameLayout>

    <LinearLayout android:id="@+id/drawerContent" android:layout_width="315dp" android:layout_height="match_parent" android:layout_gravity="end" android:background="@color/bg_color" android:orientation="vertical" android:clickable="true" android:focusable="true">
        <ScrollView android:layout_width="match_parent" android:layout_height="match_parent" android:padding="16dp">
            <LinearLayout android:orientation="vertical" android:layout_width="match_parent" android:layout_height="wrap_content">
                <TextView android:id="@+id/tvCustomTyposTitle" android:layout_width="wrap_content" android:layout_height="wrap_content" android:text="自定义错词库" android:textSize="16sp" android:textStyle="bold" android:textColor="@color/text_primary" android:layout_marginBottom="8dp"/>
                <com.app.dedede.FlowLayout android:id="@+id/llCustomTypos" android:layout_width="match_parent" android:layout_height="wrap_content"/>
                <Button android:id="@+id/btnExpandTypos" android:layout_width="match_parent" android:layout_height="36dp" android:text="展开更多" android:textSize="12sp" android:backgroundTint="#E0E0E0" android:textColor="@color/text_primary" android:visibility="gone" android:layout_marginTop="8dp" android:layout_marginBottom="8dp" android:insetTop="0dp" android:insetBottom="0dp"/>
                <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content" android:orientation="horizontal" android:gravity="center_vertical" android:layout_marginTop="8dp">
                    <EditText android:id="@+id/etOriginal" android:layout_width="0dp" android:layout_weight="1" android:layout_height="40dp" android:maxLength="5" android:hint="原始文本" android:textColorHint="#BDBDBD" android:background="@color/card_bg" android:padding="8dp" android:textSize="13sp" android:textColor="@color/text_primary"/>
                    <TextView android:id="@+id/tvCustomTyposArrow" android:layout_width="wrap_content" android:layout_height="wrap_content" android:text=" → " android:textColor="@color/text_primary"/>
                    <EditText android:id="@+id/etCorrected" android:layout_width="0dp" android:layout_weight="1" android:layout_height="40dp" android:maxLength="5" android:hint="修改后" android:textColorHint="#BDBDBD" android:background="@color/card_bg" android:padding="8dp" android:textSize="13sp" android:textColor="@color/text_primary"/>
                    <Button android:id="@+id/btnAddTypo" android:layout_width="60dp" android:layout_height="40dp" android:text="添加" android:textSize="12sp" android:backgroundTint="#81C784" android:layout_marginStart="4dp" android:padding="0dp" android:insetTop="0dp" android:insetBottom="0dp"/>
                </LinearLayout>
                <TextView android:id="@+id/tvWhitelistJumpHint" android:layout_width="match_parent" android:layout_height="wrap_content" android:text="↑仅在此卡片内输入需保护的词，再点击添加即可。" android:textSize="11sp" android:textColor="#9E9E9E" android:paddingTop="3dp" android:paddingLeft="2dp" android:layout_marginBottom="16dp" android:visibility="gone"/>
                <View android:layout_width="match_parent" android:layout_height="1dp" android:background="#E0E0E0" android:layout_marginBottom="16dp"/>
                <RelativeLayout android:layout_width="match_parent" android:layout_height="wrap_content" android:layout_marginBottom="8dp">
                    <TextView android:id="@+id/tvRecentHistoryTitle" android:layout_width="wrap_content" android:layout_height="wrap_content" android:text="最近50条纠错历史" android:textSize="16sp" android:textStyle="bold" android:textColor="@color/text_primary" android:layout_centerVertical="true"/>
                    <TextView android:id="@+id/btnClearHistory" android:layout_width="wrap_content" android:layout_height="wrap_content" android:text="清空" android:textSize="14sp" android:textColor="#2196F3" android:layout_alignParentEnd="true" android:layout_centerVertical="true" android:padding="4dp" android:background="?android:attr/selectableItemBackground"/>
                </RelativeLayout>
                <LinearLayout android:id="@+id/llHistory" android:layout_width="match_parent" android:layout_height="wrap_content" android:orientation="vertical"/>
            </LinearLayout>
        </ScrollView>
    </LinearLayout>
</androidx.drawerlayout.widget.DrawerLayout>
DEDEDE_SOURCE_EOF

mkdir -p "app/src/main/res/layout"
cat > "app/src/main/res/layout/layout_floating.xml" <<'DEDEDE_SOURCE_EOF'
<?xml version="1.0" encoding="utf-8"?>
<RelativeLayout xmlns:android="http://schemas.android.com/apk/res/android" android:id="@+id/floatRoot" android:layout_width="wrap_content" android:layout_height="wrap_content" android:padding="0dp">
    <LinearLayout android:id="@+id/panelInput" android:layout_width="240dp" android:layout_height="wrap_content" android:orientation="vertical" android:background="@color/card_bg" android:padding="10dp" android:visibility="gone">
        <LinearLayout android:id="@+id/panelTopBar" android:layout_width="match_parent" android:layout_height="wrap_content" android:orientation="horizontal" android:gravity="center_vertical" android:layout_marginBottom="6dp">
            <TextView android:layout_width="0dp" android:layout_height="wrap_content" android:layout_weight="1" android:text="悬浮台" android:textSize="13sp" android:textColor="@color/text_primary" android:textStyle="bold"/>
            <Button android:id="@+id/btnFloatJump" android:layout_width="36dp" android:layout_height="32dp" android:text="↗" android:textSize="14sp" android:backgroundTint="#03A9F4" android:padding="0dp" android:insetTop="0dp" android:insetBottom="0dp"/>
            <Button android:id="@+id/btnFloatCloseAll" android:layout_width="36dp" android:layout_height="32dp" android:text="✕" android:textSize="12sp" android:backgroundTint="#E53935" android:padding="0dp" android:insetTop="0dp" android:insetBottom="0dp" android:layout_marginStart="4dp"/>
        </LinearLayout>
        <EditText android:id="@+id/editFloatInput" android:layout_width="match_parent" android:layout_height="100dp" android:hint="直接粘贴需要检查的文本..." android:gravity="top|start" android:background="@color/bg_color" android:textColor="@color/text_primary" android:padding="8dp" android:textSize="14sp"/>
        <Button android:id="@+id/btnFloatCheck" android:layout_width="match_parent" android:layout_height="40dp" android:text="开始" android:textSize="14sp" android:backgroundTint="#2196F3" android:padding="0dp" android:layout_marginTop="8dp"/>
        <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content" android:orientation="horizontal" android:layout_marginTop="6dp">
            <Button android:id="@+id/btnFloatImport" android:layout_width="0dp" android:layout_height="38dp" android:layout_weight="1" android:text="导入" android:textSize="12sp" android:backgroundTint="@color/btn_light_green_bg" android:textColor="@color/btn_light_green_text" android:padding="0dp" android:layout_marginEnd="1dp"/>
            <Button android:id="@+id/btnFloatPaste" android:layout_width="0dp" android:layout_height="38dp" android:layout_weight="1" android:text="粘贴" android:textSize="12sp" android:backgroundTint="@color/btn_light_green_bg" android:textColor="@color/btn_light_green_text" android:padding="0dp" android:layout_marginEnd="1dp"/>
            <Button android:id="@+id/btnFloatClear" android:layout_width="0dp" android:layout_height="38dp" android:layout_weight="1" android:text="清空" android:textSize="12sp" android:backgroundTint="@color/btn_light_green_bg" android:textColor="@color/btn_light_green_text" android:padding="0dp" android:layout_marginStart="1dp" android:layout_marginEnd="1dp"/>
            <Button android:id="@+id/btnFloatCopy" android:layout_width="0dp" android:layout_height="38dp" android:layout_weight="1" android:text="复制" android:textSize="12sp" android:backgroundTint="@color/btn_light_green_bg" android:textColor="@color/btn_light_green_text" android:padding="0dp" android:layout_marginStart="1dp" android:layout_marginEnd="1dp"/>
            <Button android:id="@+id/btnFloatSwitch" android:layout_width="0dp" android:layout_height="38dp" android:layout_weight="1" android:text="切换" android:textSize="12sp" android:backgroundTint="@color/btn_light_green_bg" android:textColor="@color/btn_light_green_text" android:padding="0dp" android:layout_marginStart="1dp"/>
        </LinearLayout>
    </LinearLayout>
    <FrameLayout android:id="@+id/btnCircle" android:layout_width="48dp" android:layout_height="48dp" android:layout_below="@id/panelInput" android:background="@drawable/circle_bg" android:elevation="6dp">
        <ImageView android:layout_width="24dp" android:layout_height="24dp" android:layout_gravity="center" android:src="@drawable/ic_dedede_fg"/>
        <ProgressBar android:id="@+id/circleSpin" android:layout_width="match_parent" android:layout_height="match_parent" android:visibility="invisible" android:indeterminateTint="#FFFFFF"/>
    </FrameLayout>
    <LinearLayout android:id="@+id/statusContainer" android:layout_width="wrap_content" android:layout_height="wrap_content" android:layout_below="@id/btnCircle" android:background="#A0000000" android:orientation="vertical" android:visibility="gone" android:minWidth="80dp" android:layout_marginTop="4dp">
        <TextView android:id="@+id/tvStatus" android:layout_width="wrap_content" android:layout_height="wrap_content" android:maxWidth="300dp" android:maxLines="3" android:ellipsize="end" android:textColor="#FFFFFF" android:textSize="11sp" android:paddingStart="6dp" android:paddingEnd="6dp" android:paddingTop="3dp" android:paddingBottom="3dp"/>
        <ProgressBar android:id="@+id/floatProgressBar" style="?android:attr/progressBarStyleHorizontal" android:layout_width="match_parent" android:layout_height="2dp" android:progressTint="#2196F3" android:max="100" android:progress="0" android:visibility="gone"/>
    </LinearLayout>
</RelativeLayout>
DEDEDE_SOURCE_EOF

mkdir -p "app/src/main/res/values-night"
cat > "app/src/main/res/values-night/colors.xml" <<'DEDEDE_SOURCE_EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="bg_color">#121212</color>
    <color name="card_bg">#1E1E1E</color>
    <color name="text_primary">#E0E0E0</color>
    <color name="text_secondary">#9E9E9E</color>
    <color name="btn_light_green_bg">#1B5E20</color>
    <color name="btn_light_green_text">#A5D6A7</color>
</resources>
DEDEDE_SOURCE_EOF

mkdir -p "app/src/main/res/values-night"
cat > "app/src/main/res/values-night/themes.xml" <<'DEDEDE_SOURCE_EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <style name="Theme.Dedede" parent="Theme.AppCompat.DayNight.NoActionBar">
        <item name="colorPrimary">#2196F3</item>
        <item name="colorPrimaryDark">#1976D2</item>
        <item name="colorAccent">#4CAF50</item>
        <item name="android:statusBarColor">@color/bg_color</item>
        <item name="android:windowLightStatusBar">false</item>
    </style>
</resources>
DEDEDE_SOURCE_EOF

mkdir -p "app/src/main/res/values"
cat > "app/src/main/res/values/colors.xml" <<'DEDEDE_SOURCE_EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="icon_bg">#2196F3</color>
    <color name="bg_color">#F8F9FA</color>
    <color name="card_bg">#FFFFFF</color>
    <color name="text_primary">#1A1A1A</color>
    <color name="text_secondary">#666666</color>
    <color name="btn_light_green_bg">#E8F5E9</color>
    <color name="btn_light_green_text">#2E7D32</color>
</resources>
DEDEDE_SOURCE_EOF

mkdir -p "app/src/main/res/values"
cat > "app/src/main/res/values/themes.xml" <<'DEDEDE_SOURCE_EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <style name="Theme.Dedede" parent="Theme.AppCompat.DayNight.NoActionBar">
        <item name="colorPrimary">#2196F3</item>
        <item name="colorPrimaryDark">#1976D2</item>
        <item name="colorAccent">#4CAF50</item>
        <item name="android:statusBarColor">@color/bg_color</item>
        <item name="android:windowLightStatusBar">true</item>
    </style>
</resources>
DEDEDE_SOURCE_EOF

mkdir -p "."
cat > "build.gradle" <<'DEDEDE_SOURCE_EOF'
buildscript {
    repositories { google(); mavenCentral() }
    dependencies { classpath "com.android.tools.build:gradle:8.11.1" }
}
allprojects { repositories { google(); mavenCentral() } }
DEDEDE_SOURCE_EOF

mkdir -p "."
cat > "encrypt.py" <<'DEDEDE_SOURCE_EOF'
import gzip
import hmac
import hashlib
import json
import secrets
import shutil
import tempfile
from pathlib import Path
from Crypto.Cipher import AES

MAGIC = b'DDA3'
VERSION = 1
DOMAIN = b'DEDEDE-ASSET-V2\x00'
CHUNK = 512 * 1024
GENERATED = Path('generated_security')
GENERATED.mkdir(exist_ok=True)

master = secrets.token_bytes(32)
part_a = secrets.token_bytes(32)
part_b = secrets.token_bytes(32)
part_c = bytes(master[i] ^ part_a[i] ^ part_b[i] for i in range(32))
build_token = secrets.token_bytes(16)
Path('.ci').mkdir(exist_ok=True)
Path('.ci/security_material.json').write_text(json.dumps({'master': master.hex(), 'token': build_token.hex()}, separators=(',', ':')), encoding='utf-8')

def rol8(v: int, shift: int) -> int:
    shift &= 7
    return ((v << shift) | (v >> (8 - shift))) & 0xFF if shift else v

def encode_part(part: bytes, variant: int):
    masks = secrets.token_bytes(32)
    encoded = []
    for i, value in enumerate(part):
        shift = ((i * (variant + 2) + variant) % 7) + 1
        mixed = value ^ masks[i] ^ ((i * (31 + variant * 7) + 17 * variant) & 0xFF)
        encoded.append(rol8(mixed, shift))
    return bytes(encoded), masks

def cpp_array(data: bytes) -> str:
    return ','.join(f'0x{x:02X}' for x in data)

def java_array(data: bytes) -> str:
    return ','.join(f'(byte)0x{x:02X}' for x in data)

def write_cpp_share(path: Path, function_name: str, part: bytes, variant: int) -> None:
    encoded, masks = encode_part(part, variant)
    path.write_text(f'''#include <cstdint>\n\nnamespace {{\nconstexpr uint8_t ENCODED[32] = {{{cpp_array(encoded)}}};\nconstexpr uint8_t MASKS[32] = {{{cpp_array(masks)}}};\ninline uint8_t ror8(uint8_t value, unsigned shift) {{ shift &= 7U; return shift ? static_cast<uint8_t>((value >> shift) | (value << (8U - shift))) : value; }}\n}}\n\nextern "C" void {function_name}(uint8_t out[32]) {{\n    for (unsigned i = 0; i < 32; ++i) {{\n        unsigned shift = ((i * {variant + 2}U + {variant}U) % 7U) + 1U;\n        out[i] = static_cast<uint8_t>(ror8(ENCODED[i], shift) ^ MASKS[i] ^ ((i * {31 + variant * 7}U + {17 * variant}U) & 0xFFU));\n    }}\n}}\n''', encoding='utf-8')

write_cpp_share(GENERATED / 'key-part-a.cpp', 'dededeFillKeyPartA', part_a, 1)
write_cpp_share(GENERATED / 'key-part-b.cpp', 'dededeFillKeyPartB', part_b, 2)

encoded_c, masks_c = encode_part(part_c, 3)
(GENERATED / 'GeneratedSecuritySeed.java').write_text(f'''package com.app.dedede;\n\nfinal class GeneratedSecuritySeed {{\n    private static final byte[] ENCODED = new byte[]{{{java_array(encoded_c)}}};\n    private static final byte[] MASKS = new byte[]{{{java_array(masks_c)}}};\n    private static final byte[] TOKEN = new byte[]{{{java_array(build_token)}}};\n    private GeneratedSecuritySeed() {{}}\n    private static int ror8(int value, int shift) {{ shift &= 7; return shift == 0 ? value & 0xFF : ((value >>> shift) | (value << (8 - shift))) & 0xFF; }}\n    static byte[] revealPart() {{\n        byte[] out = new byte[32];\n        for (int i = 0; i < out.length; i++) {{\n            int shift = ((i * 5 + 3) % 7) + 1;\n            out[i] = (byte)(ror8(ENCODED[i] & 0xFF, shift) ^ (MASKS[i] & 0xFF) ^ ((i * 52 + 51) & 0xFF));\n        }}\n        return out;\n    }}\n    static byte[] buildToken() {{ return TOKEN.clone(); }}\n}}\n''', encoding='utf-8')

def derive_key(salt: bytes, asset_name: str) -> bytes:
    message = DOMAIN + build_token + salt + asset_name.encode('utf-8')
    return hmac.new(master, message, hashlib.sha256).digest()

def gzip_source(source: Path, level: int, patch_zip_header: bool) -> Path:
    fd, name = tempfile.mkstemp(prefix='dedede_', suffix='.gz')
    import os
    os.close(fd)
    target = Path(name)
    try:
        with source.open('rb') as src, target.open('wb') as raw_out:
            with gzip.GzipFile(fileobj=raw_out, mode='wb', compresslevel=level, mtime=0) as gz:
                first = src.read(2)
                if patch_zip_header and first == b'PK':
                    gz.write(b'DE')
                else:
                    gz.write(first)
                shutil.copyfileobj(src, gz, length=CHUNK)
        return target
    except Exception:
        target.unlink(missing_ok=True)
        raise

def encrypt_asset(file_in: str, file_out: str, level: int, patch_zip_header: bool) -> None:
    source = Path(file_in)
    if not source.exists():
        print(f'跳过不存在的文件: {file_in}')
        return
    salt = secrets.token_bytes(16)
    nonce_prefix = secrets.token_bytes(8)
    flags = 1 if patch_zip_header else 0
    asset_name = Path(file_out).name
    key = derive_key(salt, asset_name)
    compressed = gzip_source(source, level, patch_zip_header)
    try:
        total_length = compressed.stat().st_size
        chunk_count = (total_length + CHUNK - 1) // CHUNK
        header = (MAGIC + bytes((VERSION, flags)) + salt + nonce_prefix
                  + CHUNK.to_bytes(4, 'big')
                  + total_length.to_bytes(8, 'big')
                  + chunk_count.to_bytes(4, 'big'))
        aad_base = header + asset_name.encode('utf-8')
        with compressed.open('rb') as src, Path(file_out).open('wb') as dst:
            dst.write(header)
            for index in range(chunk_count):
                plain = src.read(CHUNK)
                if not plain:
                    raise RuntimeError('压缩资源长度异常')
                length_bytes = len(plain).to_bytes(4, 'big')
                nonce = nonce_prefix + index.to_bytes(4, 'big')
                cipher = AES.new(key, AES.MODE_GCM, nonce=nonce, mac_len=16)
                cipher.update(aad_base + index.to_bytes(4, 'big') + length_bytes)
                encrypted, tag = cipher.encrypt_and_digest(plain)
                dst.write(length_bytes)
                dst.write(encrypted)
                dst.write(tag)
            if src.read(1):
                raise RuntimeError('压缩资源分块计数异常')
        if Path(file_out).stat().st_size <= 70:
            raise RuntimeError(f'{file_out} 加密结果异常')
    finally:
        compressed.unlink(missing_ok=True)

print('正在使用 AES-256-GCM 加固 HCAM、词表和规则文件...')
encrypt_asset('hcam_model.bin', 'sys_core_p.dat', 1, False)
encrypt_asset('错别字.txt', 'sys_typo.dat', 9, False)
Path('sys_idioms.dat').unlink(missing_ok=True)  # Remove an old local dictionary if the root file was removed.
encrypt_asset('成语.txt', 'sys_idioms.dat', 9, False)
encrypt_asset('hcam_tokenizer.json', 'sys_vocab_p.dat', 9, False)
print('AES-256-GCM 加固完成；每次构建均使用全新主密钥、盐和 Nonce。')
DEDEDE_SOURCE_EOF

mkdir -p "."
cat > "gradle.properties" <<'DEDEDE_SOURCE_EOF'
android.useAndroidX=true
android.enableJetifier=false
android.nonTransitiveRClass=true
org.gradle.caching=true
org.gradle.parallel=true
org.gradle.jvmargs=-Xmx4096m -XX:MaxMetaspaceSize=1024m -Dfile.encoding=UTF-8
DEDEDE_SOURCE_EOF

mkdir -p "."
cat > "protect_rules.py" <<'DEDEDE_SOURCE_EOF'
import gzip
import hashlib
import hmac
import json
import re
import secrets
from pathlib import Path
from Crypto.Cipher import AES

source_path = Path('app/src/main/java/com/app/dedede/MainActivity.java')
source = source_path.read_text(encoding='utf-8')
anchor = source.index('public static final List<GramRule> gramRules')
start = source.index('    public static synchronized void ensureRulesLoaded()', anchor)
end = source.index('    public static final String NUMS', start)
region = source[start:end]
literal_pattern = re.compile(r'"(?:\\.|[^"\\])*"')
strings = []
indices = {}

def replace_literal(match):
    token = match.group(0)
    value = json.loads(token)
    index = indices.get(value)
    if index is None:
        index = len(strings)
        indices[value] = index
        strings.append(value)
    return f'RuleStrings.s({index})'

protected_region = literal_pattern.sub(replace_literal, region)
source_path.write_text(source[:start] + protected_region + source[end:], encoding='utf-8')

material = json.loads(Path('.ci/security_material.json').read_text(encoding='utf-8'))
master = bytes.fromhex(material['master'])
token = bytes.fromhex(material['token'])
asset_name = 'sys_rules.dat'
salt = secrets.token_bytes(16)
nonce_prefix = secrets.token_bytes(8)
magic = b'DDA3'
version = 1
flags = 0
chunk_size = 512 * 1024
domain = b'DEDEDE-ASSET-V2\x00'
key = hmac.new(master, domain + token + salt + asset_name.encode('utf-8'), hashlib.sha256).digest()
raw = json.dumps(strings, ensure_ascii=False, separators=(',', ':')).encode('utf-8')
compressed = gzip.compress(raw, compresslevel=9, mtime=0)
total_length = len(compressed)
chunk_count = (total_length + chunk_size - 1) // chunk_size
header = (magic + bytes((version, flags)) + salt + nonce_prefix
          + chunk_size.to_bytes(4, 'big')
          + total_length.to_bytes(8, 'big')
          + chunk_count.to_bytes(4, 'big'))
aad_base = header + asset_name.encode('utf-8')
target = Path('app/src/main/assets') / asset_name
with target.open('wb') as dst:
    dst.write(header)
    for index in range(chunk_count):
        plain = compressed[index * chunk_size:(index + 1) * chunk_size]
        length_bytes = len(plain).to_bytes(4, 'big')
        nonce = nonce_prefix + index.to_bytes(4, 'big')
        cipher = AES.new(key, AES.MODE_GCM, nonce=nonce, mac_len=16)
        cipher.update(aad_base + index.to_bytes(4, 'big') + length_bytes)
        encrypted, tag = cipher.encrypt_and_digest(plain)
        dst.write(length_bytes); dst.write(encrypted); dst.write(tag)
if len(strings) < 20 or target.stat().st_size < 120:
    raise RuntimeError('规则加固结果异常')
print(f'已将 {len(strings)} 个规则/白名单字符串移出 DEX，并写入 AES-GCM 资源。')
DEDEDE_SOURCE_EOF

mkdir -p "."
cat > "settings.gradle" <<'DEDEDE_SOURCE_EOF'
rootProject.name = "dedede"
include ':app'
DEDEDE_SOURCE_EOF

python3 encrypt.py
mkdir -p app/src/main/assets app/src/main/res/mipmap-xxxhdpi
cp generated_security/GeneratedSecuritySeed.java app/src/main/java/com/app/dedede/
cp generated_security/key-part-a.cpp generated_security/key-part-b.cpp app/src/main/cpp/
cp sys_core_p.dat sys_vocab_p.dat sys_typo.dat app/src/main/assets/
rm -f app/src/main/assets/sys_idioms.dat
if [ -f sys_idioms.dat ]; then cp sys_idioms.dat app/src/main/assets/; fi
cp app_icon.png app/src/main/res/mipmap-xxxhdpi/ic_launcher.png
python3 protect_rules.py

# =================== Android 普通版 / 兰特供版 ====================
# 两个版本复用上方生成的同一套 Java、XML、规则与模型。
# 仅在构建前改动所需颜色和图标；以后添加功能无须复制第二份源码。
apply_android_skin() {
  local skin="$1"
  python3 - "$skin" <<'DEDEDE_SKIN_PY'
from pathlib import Path
import re
import shutil
import sys

skin = sys.argv[1]
if skin not in ('normal', 'lan'):
    raise SystemExit('无效皮肤版本：' + skin)
res = Path('app/src/main/res')

def replace_exact(relative, old, new):
    path = res / relative
    source = path.read_text(encoding='utf-8')
    found = source.count(old)
    if found != 1:
        raise RuntimeError(f'{path}：目标内容应有 1 处，实际 {found} 处：{old}')
    path.write_text(source.replace(old, new, 1), encoding='utf-8')

def change_button(relative, button_id, original, replacement, add_text_color=False):
    path = res / relative
    source = path.read_text(encoding='utf-8')
    pattern = re.compile(r'<(?:Button|androidx\.appcompat\.widget\.AppCompatButton)\b[^>]*\bandroid:id="@\+id/' + re.escape(button_id) + r'"[^>]*>', re.S)
    matches = list(pattern.finditer(source))
    if len(matches) != 1:
        raise RuntimeError(f'{path}：按钮 {button_id} 应有 1 处，实际 {len(matches)} 处')
    match = matches[0]
    tag = match.group()
    if tag.count(original) != 1:
        raise RuntimeError(f'{path}：按钮 {button_id} 的默认样式不符')
    tag = tag.replace(original, replacement, 1)
    if add_text_color:
        if 'android:textColor=' in tag:
            raise RuntimeError(f'{path}：按钮 {button_id} 已设置文字颜色，停止覆盖')
        tag = tag[:-2] + ' android:textColor="#59364A"/>' if tag.endswith('/>') else tag[:-1] + ' android:textColor="#59364A">'
    path.write_text(source[:match.start()] + tag + source[match.end():], encoding='utf-8')

# Keep the normal package ID for upgrades; Lan gets its own data and permissions.
project = Path('app/build.gradle')
source = project.read_text(encoding='utf-8')
package = 'com.app.dededi.pte.lan' if skin == 'lan' else 'com.app.dededi.pte'
source, count = re.subn(r'applicationId "com\.app\.dededi\.pte(?:\.lan)?"',
                        'applicationId "' + package + '"', source)
if count != 1:
    raise RuntimeError('应用标识配置异常，停止构建')
project.write_text(source, encoding='utf-8')
manifest = Path('app/src/main/AndroidManifest.xml')
source = manifest.read_text(encoding='utf-8')
source, count = re.subn(r'android:label="纠错 Pro(?: · 兰)?"',
                        'android:label="' + ('纠错 Pro · 兰' if skin == 'lan' else '纠错 Pro') + '"', source)
if count != 1:
    raise RuntimeError('应用名称配置异常，停止构建')
manifest.write_text(source, encoding='utf-8')

if skin == 'lan':
    # 兰特供版独立安装；共用代码，只调整指定图标和配色。
    replace_exact('drawable/bg_check_gradient.xml',
                  '<solid android:color="#2196F3"/>', '<solid android:color="#F69BC2"/>')
    replace_exact('drawable/circle_btn_bg.xml',
                  '<solid android:color="#03A9F4"/>', '<solid android:color="#F69BC2"/>')
    replace_exact('drawable/circle_bg.xml',
                  '<solid android:color="#2196F3"/>', '<solid android:color="#F69BC2"/>')
    change_button('layout/activity_main.xml', 'btnFont',
                  'android:textColor="#2196F3"', 'android:textColor="#DE4E8C"')
    change_button('layout/activity_main.xml', 'btnFloat',
                  'android:textColor="#FFFFFF"', 'android:textColor="#59364A"')
    for button in ('btnImport', 'btnPaste', 'btnClear', 'btnCopy', 'btnSaveTxt'):
        change_button('layout/activity_main.xml', button,
                      'android:backgroundTint="@color/btn_light_green_bg"', 'android:backgroundTint="#D9EEFF"')
        change_button('layout/activity_main.xml', button,
                      'android:textColor="@color/btn_light_green_text"', 'android:textColor="#214F78"')
    change_button('layout/activity_main.xml', 'btnCheck',
                  'android:textColor="#ECF5FF"', 'android:textColor="#59364A"')
    change_button('layout/layout_floating.xml', 'btnFloatCheck',
                  'android:backgroundTint="#2196F3"', 'android:backgroundTint="#F69BC2"',
                  add_text_color=True)

icon = Path('lan.png' if skin == 'lan' else 'app_icon.png')
if not icon.is_file() or icon.stat().st_size < 32 or icon.read_bytes()[:8] != b'\x89PNG\r\n\x1a\n':
    raise RuntimeError(f'找不到有效的 PNG 图标：{icon}（应放仓库根目录）')
shutil.copyfile(icon, res / 'mipmap-xxxhdpi/ic_launcher.png')
print(f'Android 皮肤已配置：{skin}，图标：{icon}')
DEDEDE_SKIN_PY
}

case "$BUILD_MODE" in
  normal) android_variants=(normal) ;;
  lan)    android_variants=(lan) ;;
  both)   android_variants=(normal lan) ;;
esac

# --prepare-only 保持原有含义：仅生成工程，不运行 Gradle。
# both 模式的预备工程为普通版，实际构建时才分别生成两种 APK。
if [[ "${1:-}" == "--prepare-only" ]]; then
  apply_android_skin "${android_variants[0]}"
  exit 0
fi

mkdir -p dist
# 避免切换 BUILD_MODE 后混入上次构建留下的另一版本文件。
rm -f dist/Dedede-Normal.apk dist/Dedede-Lan.apk dist/Dedede-Normal.zip dist/Dedede-Lan.zip
for skin in "${android_variants[@]}"; do
  echo "====== 开始构建 Android ${skin} 版 ======" 
  apply_android_skin "$skin"
  if ! gradle --no-daemon assembleRelease --stacktrace --console=plain > "build_${skin}.log" 2>&1; then
    tail -n 300 "build_${skin}.log"
    exit 1
  fi
  test -s app/build/outputs/apk/release/app-release.apk
  if [[ "$skin" == normal ]]; then
    cp app/build/outputs/apk/release/app-release.apk dist/Dedede-Normal.apk
  else
    cp app/build/outputs/apk/release/app-release.apk dist/Dedede-Lan.apk
  fi
done

# 兼容旧工作流原有的 APK 路径。双版本时旧路径默认放普通版。
if [[ -f dist/Dedede-Normal.apk ]]; then
  cp dist/Dedede-Normal.apk Dedede-HCAM-V2-PTE.apk
else
  cp dist/Dedede-Lan.apk Dedede-HCAM-V2-PTE.apk
fi

# 额外提供 ZIP 备份；dist/*.apk 是可以直接安装的原始 APK。
python3 - <<'DEDEDE_ZIP_PY'
from pathlib import Path
from zipfile import ZipFile, ZIP_STORED
for apk in sorted(Path('dist').glob('Dedede-*.apk')):
    with ZipFile(apk.with_suffix('.zip'), 'w', compression=ZIP_STORED) as z:
        z.write(apk, arcname=apk.name)
print('已完成 APK 和 ZIP：', ', '.join(p.name for p in sorted(Path('dist').iterdir())))
DEDEDE_ZIP_PY
