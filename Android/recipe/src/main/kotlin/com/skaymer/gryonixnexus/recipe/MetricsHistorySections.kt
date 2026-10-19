package com.skaymer.gryonixnexus.recipe

import com.skaymer.gryonixnexus.catalog.AppLanguage
import com.skaymer.gryonixnexus.catalog.SH
import com.skaymer.gryonixnexus.catalog.embedding

internal object MetricsHistorySections {
    const val COLLECTOR_PATH = "/opt/gryonixnexus-metrics-collector.sh"
    const val UNIT_PATH = "/etc/systemd/system/gryonixnexus-metrics.service"
    const val DATA_DIRECTORY = "/var/lib/gryonixnexus/metrics"

    data class Bucket(val name: String, val period: Int, val keep: Int)

    val buckets = listOf(
        Bucket("10s", 10, 720),        // 2 hours
        Bucket("1m", 60, 720),         // 12 hours
        Bucket("10m", 600, 432),       // 3 days
        Bucket("1h", 3_600, 336),      // 2 weeks
        Bucket("1d", 86_400, 400),     // ~13 months
        Bucket("1w", 604_800, 260)     // 5 years
    )

    /** The daemon itself */
    val collectorScript = """
    #!/usr/bin/env bash
    # Managed by gryonixNexus — samples host metrics every 10 seconds and keeps
    # downsampled history buckets as CSV files under /var/lib/gryonixnexus/metrics.
    # Columns: epoch,cpu%,memUsed,memTotal,diskUsed,diskTotal,netRx/s,netTx/s,
    # ioRead/s,ioWrite/s,load1,tempC. Empty field = no data for that sample.
    # Power: power-<bucket>.csv, columns epoch,watts,sensor, when a sensor exists.
    # Disks: disks-<bucket>.csv, columns epoch,mount,used,total, one row per filesystem.
    set -euo pipefail

    DIR=/var/lib/gryonixnexus/metrics
    STEP=10
    install -d -m 755 /var/lib/gryonixnexus "${SH}DIR"

    cpu_ticks() { awk '${SH}1=="cpu"{t=0; for(i=2;i<=9;i++) t+=${SH}i; print t, ${SH}5+${SH}6; exit}' /proc/stat; }
    mem_bytes() { awk '/^MemTotal:/{t=${SH}2*1024} /^MemAvailable:/{a=${SH}2*1024} END{print t-a, t}' /proc/meminfo; }
    disk_bytes() {
      { df -B1 --output=target,size,used -x tmpfs -x devtmpfs -x overlay 2>/dev/null || true; } \
        | awk 'NR>1 { if (${SH}1=="/") {s=${SH}2; u=${SH}3; f=1} else if (!f && ${SH}2+0>s+0) {s=${SH}2; u=${SH}3} } END{print u+0, s+0}'
    }
    # Every real filesystem once: mount,used,total.
    disk_rows() {
      { df -B1 --output=source,target,size,used -x tmpfs -x devtmpfs -x overlay -x squashfs -x efivarfs 2>/dev/null || true; } \
        | awk 'NR>1 && NF==4 && ${SH}3+0>0 && ${SH}2 !~ /,/ && ${SH}2 !~ /^\/(boot|snap|run|proc|sys|dev)(\/|${SH})/ && !seen[${SH}1]++ {print ${SH}2","${SH}4","${SH}3}'
    }
    net_bytes() {
      awk -F: 'NF==2 {name=${SH}1; gsub(/[ \t]/,"",name); if (name ~ /^(lo|veth.*|docker.*|br-.*|virbr.*|wg.*|awg.*|tun.*|tap.*|tailscale.*|zt.*|cali.*|flannel.*|cni.*|ifb.*|dummy.*)${SH}/) next;
                      split(${SH}2,a," "); rx+=a[1]; tx+=a[9]} END{print rx+0, tx+0}' /proc/net/dev
    }
    io_bytes() {
      awk '${SH}3 ~ /^(sd[a-z]+|vd[a-z]+|xvd[a-z]+|hd[a-z]+|nvme[0-9]+n[0-9]+|mmcblk[0-9]+)${SH}/ \
             {r+=${SH}6*512; w+=${SH}10*512} END{print r+0, w+0}' /proc/diskstats
    }
    load_one() { awk '{print ${SH}1}' /proc/loadavg; }
    temp_c() {
      { cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null || true; } \
        | awk '${SH}1>0 && ${SH}1<150000 { if (${SH}1>m) m=${SH}1 } END{ if (m>0) printf "%.1f", m/1000 }'
    }
    rate() { awk -v c="${SH}1" -v p="${SH}2" -v s="${SH}STEP" 'BEGIN{d=c-p; if (d<0) d=0; printf "%d", d/s}'; }

    # Power sensors. Each prints watts, or nothing when absent.
    POWERCAP=/sys/class/powercap
    rapl_domains() {
      local d
      for d in "${SH}POWERCAP"/intel-rapl:*; do
        case "${SH}{d##*/}" in *:*:*) continue ;; esac
        if [ -r "${SH}d/energy_uj" ]; then echo "${SH}d"; fi
      done
    }
    # Energy counter and its wrap range in microjoules; psys covers the platform.
    rapl_uj() {
      local d name domains total=0 range=0
      domains=${SH}(rapl_domains)
      [ -n "${SH}domains" ] || return 0
      for d in ${SH}domains; do
        name=${SH}(cat "${SH}d/name" 2>/dev/null || true)
        if [ "${SH}name" = psys ]; then domains=${SH}d; break; fi
      done
      for d in ${SH}domains; do
        total=${SH}(( total + ${SH}(cat "${SH}d/energy_uj") ))
        range=${SH}(( range + ${SH}(cat "${SH}d/max_energy_range_uj" 2>/dev/null || echo 0) ))
      done
      echo "${SH}total ${SH}range"
    }
    ipmi_w() {
      if [ ! -e /dev/ipmi0 ] || ! command -v ipmitool >/dev/null 2>&1; then return 0; fi
      timeout 5 ipmitool dcmi power reading 2>/dev/null \
        | awk -F: '/Instantaneous power reading/ {gsub(/[^0-9.]/, "", ${SH}2); if (${SH}2+0>0) printf "%.1f", ${SH}2; exit}'
    }
    hwmon_w() {
      local f name
      for f in /sys/class/hwmon/hwmon*/power1_average /sys/class/hwmon/hwmon*/power1_input; do
        [ -r "${SH}f" ] || continue
        name=${SH}(cat "${SH}{f%/*}/name" 2>/dev/null || true)
        case "${SH}name" in amdgpu|radeon|nouveau|i915|xe) continue ;; esac
        awk '${SH}1>0 {printf "%.1f", ${SH}1/1000000}' "${SH}f"
        return 0
      done
    }
    pi_w() {
      command -v vcgencmd >/dev/null 2>&1 || return 0
      vcgencmd pmic_read_adc 2>/dev/null | awk '
        { key=substr(${SH}1, 1, length(${SH}1)-2); v=${SH}2; sub(/.*=/, "", v); sub(/[AV]${SH}/, "", v) }
        ${SH}1 ~ /_A${SH}/ {a[key]=v}
        ${SH}1 ~ /_V${SH}/ {u[key]=v}
        END { for (k in a) if (k in u) w+=a[k]*u[k]; if (w>0) printf "%.1f", w }'
    }
    ups_w() {
      command -v upsc >/dev/null 2>&1 || return 0
      local ups
      ups=${SH}(upsc -l 2>/dev/null | head -n 1)
      [ -n "${SH}ups" ] || return 0
      upsc "${SH}ups" 2>/dev/null | awk -F': ' '
        /^ups.realpower:/ {r=${SH}2} /^ups.load:/ {l=${SH}2} /^ups.realpower.nominal:/ {n=${SH}2}
        END { if (r>0) printf "%.1f", r; else if (l>0 && n>0) printf "%.1f", l*n/100 }'
    }


    # Keep only the newest <max> rows of <file>.
    trim() {
      local file=${SH}1 max=${SH}2 lines tmp
      [ -f "${SH}file" ] || return 0
      lines=${SH}(wc -l < "${SH}file")
      if [ "${SH}lines" -gt "${SH}(( max + max / 10 ))" ]; then
        tmp=${SH}(mktemp "${SH}DIR/.trim.XXXXXX")
        tail -n "${SH}max" "${SH}file" > "${SH}tmp"
        mv "${SH}tmp" "${SH}file"
        chmod 644 "${SH}file"
      fi
    }

    # Average the source rows inside the just-closed <period> window and
    # append one row to <target>. No-op while the window is still open, when
    # it was already written, or when the source has no rows in it (gap).
    aggregate() {
      local target=${SH}1 source=${SH}2 period=${SH}3 keep=${SH}4 now start last row
      [ -f "${SH}source" ] || return 0
      now=${SH}(date +%s)
      start=${SH}(( now / period * period - period ))
      last=-1
      if [ -f "${SH}target" ]; then
        last=${SH}(tail -n 1 "${SH}target" | cut -d, -f1)
        case "${SH}last" in ''|*[!0-9]*) last=-1 ;; esac
      fi
      [ "${SH}last" -lt "${SH}start" ] || return 0
      row=${SH}(awk -F, -v s="${SH}start" -v e=${SH}(( start + period )) '
        ${SH}1>=s && ${SH}1<e {
          n++
          if (${SH}2!="") {c+=${SH}2; cn++}
          mu+=${SH}3; mt=${SH}4; du+=${SH}5; dt=${SH}6
          if (${SH}7!="") {rx+=${SH}7; rxn++}
          if (${SH}8!="") {tx+=${SH}8; txn++}
          if (${SH}9!="") {ir+=${SH}9; irn++}
          if (${SH}10!="") {iw+=${SH}10; iwn++}
          l+=${SH}11
          if (${SH}12!="") {tp+=${SH}12; tn++}
        }
        END {
          if (!n) exit 0
          printf "%d,", s
          if (cn) printf "%.1f", c/cn
          printf ",%d,%d,%d,%d,", mu/n, mt, du/n, dt
          if (rxn) printf "%d", rx/rxn
          printf ","
          if (txn) printf "%d", tx/txn
          printf ","
          if (irn) printf "%d", ir/irn
          printf ","
          if (iwn) printf "%d", iw/iwn
          printf ",%.2f,", l/n
          if (tn) printf "%.1f", tp/tn
          printf "\n"
        }' "${SH}source")
      [ -n "${SH}row" ] || return 0
      printf '%s\n' "${SH}row" >> "${SH}target"
      chmod 644 "${SH}target"
      trim "${SH}target" "${SH}keep"
    }


    # Average watts inside the just-closed <period> window, same rules as above.
    aggregate_power() {
      local target=${SH}1 source=${SH}2 period=${SH}3 keep=${SH}4 now start last row
      [ -f "${SH}source" ] || return 0
      now=${SH}(date +%s)
      start=${SH}(( now / period * period - period ))
      last=-1
      if [ -f "${SH}target" ]; then
        last=${SH}(tail -n 1 "${SH}target" | cut -d, -f1)
        case "${SH}last" in ''|*[!0-9]*) last=-1 ;; esac
      fi
      [ "${SH}last" -lt "${SH}start" ] || return 0
      row=${SH}(awk -F, -v s="${SH}start" -v e=${SH}(( start + period )) '
        ${SH}1>=s && ${SH}1<e && ${SH}2!="" {w+=${SH}2; n++; src=${SH}3}
        END { if (n) printf "%d,%.1f,%s\n", s, w/n, src }' "${SH}source")
      [ -n "${SH}row" ] || return 0
      printf '%s\n' "${SH}row" >> "${SH}target"
      chmod 644 "${SH}target"
      trim "${SH}target" "${SH}keep"
    }

    # Average each filesystem inside the just-closed <period> window.
    aggregate_disks() {
      local target=${SH}1 source=${SH}2 period=${SH}3 keep=${SH}4 now start last row
      [ -f "${SH}source" ] || return 0
      now=${SH}(date +%s)
      start=${SH}(( now / period * period - period ))
      last=-1
      if [ -f "${SH}target" ]; then
        last=${SH}(tail -n 1 "${SH}target" | cut -d, -f1)
        case "${SH}last" in ''|*[!0-9]*) last=-1 ;; esac
      fi
      [ "${SH}last" -lt "${SH}start" ] || return 0
      row=${SH}(awk -F, -v s="${SH}start" -v e=${SH}(( start + period )) '
        ${SH}1>=s && ${SH}1<e && NF==4 {u[${SH}2]+=${SH}3; t[${SH}2]=${SH}4; n[${SH}2]++}
        END { for (m in n) printf "%d,%s,%d,%d\n", s, m, u[m]/n[m], t[m] }' "${SH}source")
      [ -n "${SH}row" ] || return 0
      printf '%s\n' "${SH}row" >> "${SH}target"
      chmod 644 "${SH}target"
      trim "${SH}target" ${SH}(( keep * 16 ))
    }

    prev_total=0 prev_idle=0 prev_rx=0 prev_tx=0 prev_ir=0 prev_iw=0 have_prev=0
    prev_uj=0 prev_rapl_at=0 have_rapl=0

    while :; do
      now=${SH}(date +%s)
      read -r total idle < <(cpu_ticks)
      read -r mem_used mem_total < <(mem_bytes)
      read -r disk_used disk_total < <(disk_bytes)
      read -r rx tx < <(net_bytes)
      read -r io_r io_w < <(io_bytes)
      load=${SH}(load_one)
      temp=${SH}(temp_c)

      cpu="" rx_rate="" tx_rate="" ir_rate="" iw_rate=""
      if [ "${SH}have_prev" -eq 1 ]; then
        cpu=${SH}(awk -v t=${SH}((total - prev_total)) -v i=${SH}((idle - prev_idle)) \
          'BEGIN{ if (t>0) { p=(t-i)*100/t; if (p<0) p=0; if (p>100) p=100; printf "%.1f", p } }')
        rx_rate=${SH}(rate "${SH}rx" "${SH}prev_rx")
        tx_rate=${SH}(rate "${SH}tx" "${SH}prev_tx")
        ir_rate=${SH}(rate "${SH}io_r" "${SH}prev_ir")
        iw_rate=${SH}(rate "${SH}io_w" "${SH}prev_iw")
      fi

      printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
        "${SH}now" "${SH}cpu" "${SH}mem_used" "${SH}mem_total" "${SH}disk_used" "${SH}disk_total" \
        "${SH}rx_rate" "${SH}tx_rate" "${SH}ir_rate" "${SH}iw_rate" "${SH}load" "${SH}temp" >> "${SH}DIR/10s.csv"
      chmod 644 "${SH}DIR/10s.csv"
      trim "${SH}DIR/10s.csv" 720

      power="" psrc=""
      for probe in ipmi hwmon pi; do
        power=${SH}("${SH}{probe}_w")
        if [ -n "${SH}power" ]; then psrc=${SH}probe; break; fi
      done
      rapl=${SH}(rapl_uj)
      if [ -z "${SH}power" ] && [ -n "${SH}rapl" ] && [ "${SH}have_rapl" -eq 1 ]; then
        power=${SH}(awk -v c="${SH}{rapl% *}" -v p="${SH}prev_uj" -v r="${SH}{rapl#* }" -v s=${SH}(( now - prev_rapl_at )) \
          'BEGIN{d=c-p; if (d<0) d+=r; if (d>0 && s>0) printf "%.1f", d/1000000/s}')
        if [ -n "${SH}power" ]; then psrc=rapl; fi
      fi
      if [ -n "${SH}rapl" ]; then prev_uj=${SH}{rapl% *}; prev_rapl_at=${SH}now; have_rapl=1; fi
      if [ -z "${SH}power" ]; then
        power=${SH}(ups_w)
        if [ -n "${SH}power" ]; then psrc=ups; fi
      fi
      if [ -n "${SH}power" ]; then
        printf '%s,%s,%s\n' "${SH}now" "${SH}power" "${SH}psrc" >> "${SH}DIR/power-10s.csv"
        chmod 644 "${SH}DIR/power-10s.csv"
        trim "${SH}DIR/power-10s.csv" 720
      fi

      disk_rows | awk -v t="${SH}now" '{print t","${SH}0}' >> "${SH}DIR/disks-10s.csv"
      chmod 644 "${SH}DIR/disks-10s.csv"
      trim "${SH}DIR/disks-10s.csv" ${SH}(( 720 * 16 ))

      aggregate "${SH}DIR/1m.csv"  "${SH}DIR/10s.csv" 60      720
      aggregate "${SH}DIR/10m.csv" "${SH}DIR/1m.csv"  600     432
      aggregate "${SH}DIR/1h.csv"  "${SH}DIR/10m.csv" 3600    336
      aggregate "${SH}DIR/1d.csv"  "${SH}DIR/1h.csv"  86400   400
      aggregate "${SH}DIR/1w.csv"  "${SH}DIR/1d.csv"  604800  260
      aggregate_power "${SH}DIR/power-1m.csv"  "${SH}DIR/power-10s.csv" 60      720
      aggregate_power "${SH}DIR/power-10m.csv" "${SH}DIR/power-1m.csv"  600     432
      aggregate_power "${SH}DIR/power-1h.csv"  "${SH}DIR/power-10m.csv" 3600    336
      aggregate_power "${SH}DIR/power-1d.csv"  "${SH}DIR/power-1h.csv"  86400   400
      aggregate_power "${SH}DIR/power-1w.csv"  "${SH}DIR/power-1d.csv"  604800  260
      aggregate_disks "${SH}DIR/disks-1m.csv"  "${SH}DIR/disks-10s.csv" 60      720
      aggregate_disks "${SH}DIR/disks-10m.csv" "${SH}DIR/disks-1m.csv"  600     432
      aggregate_disks "${SH}DIR/disks-1h.csv"  "${SH}DIR/disks-10m.csv" 3600    336
      aggregate_disks "${SH}DIR/disks-1d.csv"  "${SH}DIR/disks-1h.csv"  86400   400
      aggregate_disks "${SH}DIR/disks-1w.csv"  "${SH}DIR/disks-1d.csv"  604800  260

      prev_total=${SH}total prev_idle=${SH}idle prev_rx=${SH}rx prev_tx=${SH}tx prev_ir=${SH}io_r prev_iw=${SH}io_w
      have_prev=1
      sleep "${SH}STEP"
    done
    """.trimIndent()

    private val systemdUnit = """
    [Unit]
    Description=gryonixNexus metrics history collector
    After=local-fs.target

    [Service]
    ExecStart=/opt/gryonixnexus-metrics-collector.sh
    Restart=always
    RestartSec=5
    Nice=10
    IOSchedulingClass=idle

    [Install]
    WantedBy=multi-user.target
    """.trimIndent()

    /** Setup-script section: installs the daemon and (re)starts it */
    fun install(language: AppLanguage): String = """
        log "${L10nScripts.installingMetricsCollector(language)}"
        @COLLECTOR@
        chmod 755 $COLLECTOR_PATH
        @UNIT@
        systemctl daemon-reload
        systemctl enable gryonixnexus-metrics >/dev/null 2>&1 || true
        systemctl restart gryonixnexus-metrics
        """.trimIndent().embedding(
        "COLLECTOR" to BashSections.writeFile(COLLECTOR_PATH, collectorScript, "EOF_METRICS"),
        "UNIT" to BashSections.writeFile(UNIT_PATH, systemdUnit, "EOF_METRICS_UNIT")
    )
}
