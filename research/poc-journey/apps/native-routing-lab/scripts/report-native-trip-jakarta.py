#!/usr/bin/env python3
"""Create a Jakarta XCTest report from actual JUnit and itinerary artifacts."""
import argparse
import json
import re
from pathlib import Path
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from zoneinfo import ZoneInfo

DESCRIPTIONS = {
 'testAdaptiveEstimatedGainTriggersValidatedOptimization': 'Skenario sintetis dengan peluang penghematan memicu optimizer; hasil nyata divalidasi dan membaik.',
 'testAdaptiveJakartaSkipsExtraRequestsWithoutChangingSchedule': 'Adaptif memakai 30 request; jadwal tetap sama dan perkiraan tidak menjadi data provider.',
 'testForcedFullHybridRemainsAvailableForComparison': 'Override hybrid penuh tetap memakai 88 request dengan itinerary acuan yang sama.',
 'testAdaptiveOneAndTwoDestinationsCoverAllOrdersWithoutSnapshot': 'Satu/dua tujuan selesai setelah semua urutan sudah divalidasi.',
 'testAdaptiveLargeWaitingTriggersOptimization': 'Waktu tunggu besar tetap memicu pencarian tambahan.',
 'testAdaptiveNoWaitingDoesNotHideUnknownRoadShortcuts': 'Biaya ruas yang belum diketahui tetap memicu pencarian ketika tidak ada waktu tunggu penyangga.',
 'testAdaptiveTightClosingMarginStillRunsOptimization': 'Margin jam tutup sempit tetap menjalankan optimizer.',
 'testAdaptiveScreeningPreservesWeatherAndPrivateCarSearch': 'Cuaca/mobil pribadi tetap dicari; screening tidak mengambil ETA baru.',
 'testAdaptiveTinyScreeningBudgetFallsBackToSearch': 'Budget screening yang tidak cukup tidak dianggap bukti baseline memadai.',

 'testRecordedFourStopScheduleHasExpectedTravelWaitAndReturn': 'Empat tujuan: ETA, tunggu buka, singgah dan ruas kembali cocok dengan acuan tetap.',
 'testLessTravelDoesNotBeatAnEarlierTripFinish': 'Perjalanan lebih pendek tidak mengalahkan total trip lebih singkat.',
 'testAllSevenNativeMethodsPreserveStopsAndReachTheKnownFourStopReference': 'Tujuh algoritme mempertahankan semua tujuan dan mencapai acuan empat tujuan ini.',
 'testCurrentBaselinePipelineUsesElapsedObjective': 'Baseline versi sekarang menggunakan tujuan elapsed.',
 'testHybridPipelineKeepsValidatedBaselineAndRequestBudget': 'Hybrid mempertahankan baseline, membatasi request dan tidak mengarang rekomendasi cuaca.',
 'testCentralJakartaSubsetReturnsToSudirman': 'Subset Monas–Grand Indonesia kembali ke Sudirman.',
 'testNorthJakartaSubsetWaitsUntilKelapaGadingOpens': 'Subset Kota Tua–Kelapa Gading menunggu sampai 10.00.',
 'testSyntheticHoursForEveryStopAreAllRespected': 'Semua jam buka/tutup asumsi sintetis diterapkan pada empat tujuan.',
 'testShuffledInputStillVisitsEveryPlaceAndRespectsOpening': 'Input acak tetap menghasilkan urutan yang layak pada fixture.',
 'testCompleteDwellAtClosingBoundaryIsAcceptedButOneMinuteEarlierIsNot': 'Akhir singgah tepat saat tutup diterima; melewati satu menit ditolak.',
 'testImpossibleOpeningWindowDoesNotProduceAFeasibleItinerary': 'Singgah 30 menit dalam jendela buka 15 menit tidak dinyatakan layak.',
 'testChangedDateRejectsStaleOpeningHoursBeforeAnyETARequest': 'Perubahan tanggal menolak jam operasional lama sebelum request ETA.',
 'testMissingAllRoutesIntoKelapaGadingRemainsUnknown': 'ETA hilang tetap unknown, tanpa durasi nol atau klaim optimum.',
 'testUnavailableTransitAndWalkingLimitDoNotInventTransport': 'Tanpa mobil, transit tidak tersedia dan batas berjalan tidak dilewati diam-diam.',
 'testLongerDwellPropagatesAndCanReplaceOpeningWait': 'Durasi singgah 60 menit menggantikan sebagian waktu menunggu buka.',
 'testSyntheticPeakETAUsesActualDepartureAfterDwell': 'ETA sintetis naik setelah +120 menit; waktu keberangkatan aktual digunakan.',
 'testTripCrossingMidnightIsNotSilentlyShortened': 'Trip melewati tengah malam ditandai tidak lengkap tanpa membuang input.',
}

def short(name):
    return {'National Monument':'Monas', 'Summarecon Mall Kelapa Gading':'Kelapa Gading', 'Stasiun sudirman':'Sudirman'}.get(name,name)

def clock(value):
    if not value:return '—'
    return datetime.fromisoformat(value.replace('Z','+00:00')).astimezone(ZoneInfo('Asia/Jakarta')).strftime('%H:%M:%S')

def minutes(seconds):
    return f'{seconds/60:.2f}'.replace('.',',')


def recover_junit_from_xctest_log(out):
    """SwiftPM on this host emits XCTest console events but no requested xUnit file."""
    log=(out/'test.log').read_text()
    started=re.compile(r"^Test Case '-\[([^ ]+) ([^\]]+)\]' started\.")
    finished=re.compile(r"^Test Case '-\[([^ ]+) ([^\]]+)\]' (passed|failed|skipped) \(([0-9.]+) seconds?\)\.")
    cases=[];errors=[]
    for line in log.splitlines():
        if started.match(line):errors=[]
        match=finished.match(line)
        if match:
            classname,name,status,seconds=match.groups()
            cases.append((classname,name,status,float(seconds),list(errors)))
        elif ': error:' in line or 'failed -' in line:errors.append(line)
    summaries=re.findall(r'Executed (\d+) tests?, with (\d+) failures?',log)
    if not cases or not summaries or int(summaries[-1][0])!=len(cases):
        return False
    failures=sum(case[2]=='failed' for case in cases)
    reported_failures=int(summaries[-1][1])
    if failures>reported_failures or (failures==0 and reported_failures>0):return False
    root=ET.Element('testsuites')
    suite=ET.SubElement(root,'testsuite',name='NativeTripJakartaTests',tests=str(len(cases)),failures=str(failures),
                        skipped=str(sum(c[2]=='skipped' for c in cases)),time=str(sum(c[3] for c in cases)))
    for classname,name,status,seconds,details in cases:
        case=ET.SubElement(suite,'testcase',classname=classname,name=name,time=str(seconds))
        if status=='failed':ET.SubElement(case,'failure',message='XCTest reported failure').text='\n'.join(details)
        if status=='skipped':ET.SubElement(case,'skipped')
    ET.indent(root)
    ET.ElementTree(root).write(out/'junit.xml',encoding='utf-8',xml_declaration=True)
    return True


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output',type=Path)
    parser.add_argument('--test-status',required=True,type=int)
    args=parser.parse_args();out=args.output
    tests=[]
    junit_source='SwiftPM xUnit output'
    if not (out/'junit.xml').exists():
        recovered=recover_junit_from_xctest_log(out)
        junit_source='Converted from actual XCTest console events; case count/failure count cross-checked against suite summary' if recovered else 'missing'
    if (out/'junit.xml').exists():
        root=ET.parse(out/'junit.xml').getroot()
        for case in root.iter('testcase'):
            name=case.get('name','').split('.')[-1]
            failures=list(case.findall('failure'))+list(case.findall('error'))
            tests.append(dict(name=name,status='failed' if failures else 'skipped' if case.find('skipped') is not None else 'passed',
                seconds=float(case.get('time','0')),detail=DESCRIPTIONS.get(name,name),
                errors=[(f.get('message','')+' '+(f.text or '')).strip() for f in failures]))
    itineraries=[json.loads(x) for x in (out/'itineraries.jsonl').read_text().splitlines()] if (out/'itineraries.jsonl').exists() else []
    manifest=json.loads((out/'manifest.json').read_text())
    passed=sum(t['status']=='passed' for t in tests);failed=sum(t['status']=='failed' for t in tests);skipped=sum(t['status']=='skipped' for t in tests)
    summary=dict(generatedAt=datetime.now(timezone.utc).isoformat(),framework=manifest['framework'],
        tests=len(tests),passed=passed,failed=failed,skipped=skipped,exitCode=args.test_status,
        allPassed=len(tests)==len(DESCRIPTIONS) and {t['name'] for t in tests}==set(DESCRIPTIONS) and failed==0 and skipped==0 and args.test_status==0,
        junitSource=junit_source,
        network=False,liveProviderLatencyMeasured=False,testExecutionSeconds=sum(t['seconds'] for t in tests),
        cases=tests,itineraries=itineraries)
    (out/'summary.json').write_text(json.dumps(summary,indent=2,ensure_ascii=False,allow_nan=False)+'\n')
    lines=['# Unit test routing Jakarta — PoC C67','',
      f"Hasil: **{passed}/{len(tests)} lulus**, {failed} gagal, {skipped} dilewati. Exit code XCTest: `{args.test_status}`.",'',
      'Suite XCTest dijalankan melalui SwiftPM pada macOS, tanpa jaringan dan tanpa membuka aplikasi/Simulator. Kode evaluator, solver, engine dan planner produksi dikompilasi tanpa perubahan; lapisan layanan memakai adapter replay yang sudah ada. Suite mencakup unit evaluator/optimizer serta integrasi pipeline dengan adapter.',
      '',f"Base commit: `{manifest['gitCommit']}`; source yang diuji adalah working tree. Hash berkas fixture, source, test dan runner tercatat pada [manifest](manifest.json).",'',
      '## Tempat dan data','',
      '- Pergi/pulang **Stasiun Sudirman**, 5 November 2026, mulai **07.00 WIB**.',
      '- Tujuan: **Monas, Grand Indonesia, Kota Tua, dan Summarecon Mall Kelapa Gading**; juga diuji dua subset dengan masing-masing dua tujuan.',
      '- Default singgah **30 menit**. Moda memakai ETA walking/transit/automobile yang terekam; konteks mobil taksi/ride-hailing. Tidak menambahkan waktu pesan/tunggu taksi atau parkir.',
      '- ETA berasal dari rekaman MapKit yang dipakai pada benchmark sebelumnya, dibekukan untuk pengujian. Ini bukan prakiraan trafik terbaru.',
      '- Fixture asli hanya memiliki jam buka Kelapa Gading **10.00**, berasal dari input pengguna; jam operasional tujuan lain dan jam tutup belum diketahui. Hasil fixture asli tidak membuktikan tempat sungguh buka pada jadwalnya.',
      '- Kasus tambahan jam buka semua tujuan, jam tutup sempit dan perubahan ETA adalah **asumsi sintetis untuk unit test**, bukan informasi operasional nyata. Tidak ada data cuaca pada suite ini.',
      '', '## Hasil test', '', '| Test | Hasil | Yang diperiksa |','|---|---|---|']
    for index,t in enumerate(tests,1):
        lines.append(f"| {index}. `{t['name']}` | {t['status'].upper()} | {t['detail']} |")
    if not tests:lines.append('| — | TIDAK BERJALAN | Periksa log build/test. |')
    tours=[c for c in itineraries if c.get('source')=='recorded_static' and c.get('kind')!='model']
    labels={'baseline_four_stops':'Baseline sekarang · 4 tujuan','hybrid_four_stops':'Hybrid sekarang · 4 tujuan',
            'central_two_stops':'Hybrid · Monas + Grand Indonesia','north_two_stops':'Hybrid · Kota Tua + Kelapa Gading'}
    tours.sort(key=lambda c:list(labels).index(c['scenario']) if c['scenario'] in labels else len(labels))
    lines += ['', '## Itinerary dengan fixture ETA asli', '',
      'Baseline di tabel ini adalah **baseline versi sekarang yang sudah memakai elapsed**, bukan default lama sebelum commit perubahan.', '',
      '| Skenario | Urutan setelah Sudirman | Perjalanan | Tunggu | Singgah | Total | Selesai WIB | Request adapter |',
      '|---|---|---:|---:|---:|---:|---|---:|']
    for c in tours:
        lines.append(f"| {labels.get(c['scenario'],c['scenario'])} | {' → '.join(map(short,c['order']))} → Sudirman | {minutes(c['travelSeconds'])} | {minutes(c['waitingSeconds'])} | {minutes(c['dwellSeconds'])} | {minutes(c['elapsedSeconds'])} | {clock(c['finish'])} | {c['requests']} |")
    lines += ['', 'Semua durasi tabel dalam menit. Dua tujuan di utara dapat selesai pada waktu yang sama dengan empat tujuan karena jam buka Kelapa Gading tetap 10.00; waktu yang tidak dipakai untuk kunjungan lain menjadi waktu tunggu.', '',
      '## Waktu komputasi dan request','',
      '**Waktu di bawah adalah eksekusi host dengan adapter tanpa jaringan, bukan waktu tunggu pengguna pada MapKit live.** Request adapter menghitung permintaan baru yang tidak terpenuhi cache; tidak ada request ke Apple.', '',
      '| Skenario | Komputasi pipeline di Mac | Request | Rentang minimum awal request berdasarkan pacing 1,2 detik |',
      '|---|---:|---:|---:|']
    for c in tours:
        lines.append(f"| {labels.get(c['scenario'],c['scenario'])} | {c['wallSeconds']*1000:.2f} ms | {c['requests']} | {max(0,c['requests']-1)*1.2:.1f} detik |")
    lines += ['', 'Kolom pacing dihitung sebagai `(jumlah request − 1) × 1,2`. Itu batas bawah rentang dari awal request pertama ke awal request terakhir jika semuanya dikirim berurutan sesuai kebijakan saat ini. Belum termasuk respons request terakhir, cuaca, pencarian lokasi atau penundaan provider. Bukan hasil pengukuran jaringan, dan tidak boleh dijumlahkan begitu saja dengan seluruh latensi tiap request karena pacing dapat bertumpang tindih dengan waktu respons.', '',
      '## Skenario sintetis tambahan','']
    for c in itineraries:
        if c.get('source','').startswith('synthetic_'):
            lines.append(f"- `{c['scenario']}`: {' → '.join(map(short,c['order']))} → Sudirman; total **{minutes(c['elapsedSeconds'])} menit**, selesai **{clock(c['finish'])} WIB**, {c['requests']} request adapter. Asumsi sintetis, tidak memvalidasi trafik atau jam operasional nyata.")
    models=[c for c in itineraries if c.get('kind')=='model']
    if models:
        lines += ['', '## Tujuh algoritme pada model yang sama','',
           '| Metode | Total menit | Evaluasi | Klaim |','|---|---:|---:|---|']
        for c in models:lines.append(f"| `{c['scenario'][6:]}` | {minutes(c['elapsedSeconds'])} | {c['evaluations']} | `{c['proof']}` |")
        lines += ['', 'Acuan 15.467 detik pada empat tujuan ini diperoleh dari enumerasi independen pada benchmark sebelumnya. Hasil semua metode sama pada kasus kecil ini; bukan bukti bahwa kualitasnya selalu sama pada input lain. Acuan model tetap tidak membuktikan optimum kondisi dunia nyata.']
    lines += ['', '## Bukti dan reproduksi','',
      '- [Hasil terstruktur dan rincian itinerary](summary.json)',
      '- [JUnit XCTest](junit.xml) — '+junit_source+'.',
      '- [Log build dan test](test.log)',
      '- [Metrik/ruas mentah](itineraries.jsonl)',
      '- [Identitas source dan konfigurasi](manifest.json)','',
      'Dari root repo:', '', '```sh','./scripts/test-native-trip-jakarta.sh /tmp/c67-jakarta-unit-results','```','',
      'Gunakan direktori output baru. Runner menghasilkan laporan ini dari hasil test sebenarnya, termasuk kegagalan. Tidak menjalankan benchmark seluruh suite sebelumnya, tidak mengubah kode aplikasi, dan tidak menguji layanan live atau iPhone fisik.']
    if failed or args.test_status:
        lines += ['', '## Kegagalan','']
        for t in tests:
            for error in t['errors']:lines.append(f"- `{t['name']}`: {error.replace(chr(10),' ')[:1600]}")
        if not tests:lines.append('Build/test belum menghasilkan JUnit. Baca `test.log`.')
    (out/'REPORT.md').write_text('\n'.join(lines)+'\n')
    print(f"XCTest Jakarta: {passed}/{len(tests)} passed; {failed} failed; {skipped} skipped; exit {args.test_status}.")
    print(f"Report: {out/'REPORT.md'}")
    if not summary['allPassed']:raise SystemExit(1)

if __name__=='__main__':main()
