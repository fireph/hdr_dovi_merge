param ($dovi, $hdr10, $out)

try {

    Write-Host "Checking frame counts..."

    $hdr_format_dovi = mediainfo --Output="Video;%HDR_Format%" $dovi
    $hdr_format_hdr10 = mediainfo --Output="Video;%HDR_Format%" $hdr10

    if (-Not ($hdr_format_dovi.contains("Dolby Vision"))) {
        Write-Host -ForegroundColor red "DoVi video is not Dolby Vision!"
        exit
    }
    if (-Not ($hdr_format_hdr10.contains("HDR10") -or $hdr_format_hdr10.contains("2086"))) {
        Write-Host -ForegroundColor red "HDR10 video is not HDR10 or HDR10+!"
        exit
    }

    $dovi_frame_count = mediainfo --Output="Video;%FrameCount%" $dovi
    $hdr10_frame_count = mediainfo --Output="Video;%FrameCount%" $hdr10

    if ($dovi_frame_count -ne $hdr10_frame_count) {
    	Write-Host -ForegroundColor red "Frame counts are different, cannot merge! dovi:${dovi_frame_count} hdr10:${hdr10_frame_count}"
    	exit
    }

    if (!(($dovi_frame_count -gt 0) -and ($hdr10_frame_count -gt 0))) {
    	Write-Host -ForegroundColor red "Frame counts are zero, cannot merge! dovi:${dovi_frame_count} hdr10:${hdr10_frame_count}"
    	exit
    }

    Write-Host "Frame counts are the same. ${dovi_frame_count}"

    Write-Host "Extracting HDR10 data..."
    ffmpeg -hide_banner -loglevel error -y -i $hdr10 -c:v copy HDR10.hevc
    Write-Host "Extracting DoVi data..."
    ffmpeg -hide_banner -loglevel error -y -i $dovi -an -c:v copy -bsf:v hevc_mp4toannexb -f hevc DV.hevc

    Write-Host "Extracting DoVi RPU data..."
    dovi_tool -m 3 extract-rpu DV.hevc
    Write-Host "Injecting DoVi RPU into HDR10..."
    dovi_tool inject-rpu -i HDR10.hevc --rpu-in RPU.bin -o HDR10_DV.hevc

    $framerate = ffprobe -v error -select_streams v -of default=noprint_wrappers=1:nokey=1 -show_entries stream=r_frame_rate $hdr10
    Write-Host "Using framerate of ${framerate}p"

    Write-Host "Merging DoVi/HDR video with original HDR10 file..."
    mkvmerge -q -o $out --default-duration "0:${framerate}p" HDR10_DV.hevc -D $hdr10

} finally {
    # Remove working files
    if (Test-Path DV.hevc) {
        Remove-Item DV.hevc
    }
    if (Test-Path HDR10.hevc) {
        Remove-Item HDR10.hevc
    }
    if (Test-Path HDR10_DV.hevc) {
        Remove-Item HDR10_DV.hevc
    }
    if (Test-Path RPU.bin) {
        Remove-Item RPU.bin
    }
}
