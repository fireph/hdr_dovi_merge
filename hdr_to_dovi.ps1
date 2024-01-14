param ($hdr, $out)

try {

    Write-Host -ForegroundColor green "---------------------------------"
    Write-Host -ForegroundColor green "Converting HDR10+ to Dolby Vision: ${hdr}"
    Write-Host -ForegroundColor green "---------------------------------"

    $hdr_format = mediainfo --Output="Video;%HDR_Format%" $hdr

    if (-Not ($hdr_format.contains("2094"))) {
        Write-Host -ForegroundColor red "Video is not HDR10+!"
        exit
    }

    $frame_count = mediainfo --Output="Video;%FrameCount%" $hdr

    if (-Not ($frame_count –gt 0)) {
        Write-Host -ForegroundColor red "Frame count is not valid!"
        exit
    }

    Write-Host "Extracting HDR10 video data..."
    ffmpeg -hide_banner -loglevel error -y -i $hdr -c:v copy HDR10.hevc

    Write-Host "Extracting HDR10 metadata..."
    hdr10plus_tool extract HDR10.hevc -o metadata.json

    $minmax_lum = mediainfo --Output="Video;%MasteringDisplay_Luminance%" HDR10.hevc
    $min_lum_str,$max_lum_str = $minmax_lum.split(', ')
    $min_lum = [math]::floor($min_lum_str.replace("min: ","").replace(" cd/m2",""))
    $max_lum = [math]::floor($max_lum_str.replace("max: ","").replace(" cd/m2",""))
    $max_cll_str = mediainfo --Output="Video;%MaxCLL%" HDR10.hevc
    $max_fall_str = mediainfo --Output="Video;%MaxFALL%" HDR10.hevc
    $max_cll = [math]::floor($max_cll_str.replace(" cd/m2",""))
    $max_fall = [math]::floor($max_fall_str.replace(" cd/m2",""))

    if ((-Not ($min_lum –ge 0)) -or (-Not ($max_lum –ge 0)) -or (-Not ($max_cll –ge 0)) -or (-Not ($max_fall –ge 0))) {
        Write-Host -ForegroundColor red "One of the luminance values is invalid!"
        Write-Host -ForegroundColor red "min_display_mastering_luminance:${min_lum}"
        Write-Host -ForegroundColor red "max_display_mastering_luminance:${max_lum}"
        Write-Host -ForegroundColor red "max_content_light_level:${max_cll}"
        Write-Host -ForegroundColor red "max_frame_average_light_level:${max_fall}"
        exit
    }

    $extraJson = @"
{
"length": ${frame_count},
"level2": [
{
"target_nits": 100
},
{
"target_nits": 600
},
{
"target_nits": 1000
},
{
"target_nits": 2000
}
],
"level6": {
"max_display_mastering_luminance": ${max_lum},
"min_display_mastering_luminance": ${min_lum},
"max_content_light_level": ${max_cll},
"max_frame_average_light_level": ${max_fall}
}
}
"@

    Add-Content extra.json $extraJson

    Write-Host "Converting HDR10+ metadata to DoVi RPU data..."
    dovi_tool generate -j extra.json --hdr10plus-json metadata.json --rpu-out RPUPlus.bin

    Write-Host "Injecting DoVi RPU into HDR10..."
    dovi_tool inject-rpu --input HDR10.hevc --rpu-in RPUPlus.bin -o HDR10_DV.hevc

    $framerate = ffprobe -v error -select_streams v -of default=noprint_wrappers=1:nokey=1 -show_entries stream=r_frame_rate $hdr
    Write-Host "Using framerate of ${framerate}p"

    Write-Host "Merging DoVi/HDR video with original file..."
    mkvmerge -q -o $out --default-duration "0:${framerate}p" HDR10_DV.hevc -D $hdr

} finally {
    # Remove working files
    if (Test-Path HDR10.hevc) {
        Remove-Item HDR10.hevc
    }
    if (Test-Path metadata.json) {
        Remove-Item metadata.json
    }
    if (Test-Path extra.json) {
        Remove-Item extra.json
    }
    if (Test-Path RPUPlus.bin) {
        Remove-Item RPUPlus.bin
    }
    if (Test-Path HDR10_DV.hevc) {
        Remove-Item HDR10_DV.hevc
    }
}
