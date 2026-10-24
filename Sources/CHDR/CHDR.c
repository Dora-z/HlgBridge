#include "CHDR.h"
#include "ultrahdr_api.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
static int check(uhdr_error_info_t result, char *error, size_t n) {
    if (result.error_code == UHDR_CODEC_OK) return 1;
    snprintf(error, n, "%s", result.has_detail ? result.detail : "Ultra HDR codec failed");
    return 0;
}
#define CHECK(expr) if (!check((expr), error, error_size)) goto fail
int hlg_encode(const uint16_t *pixels, unsigned w, unsigned h,
               const uint8_t *jpeg, size_t jpeg_size, float peak,
               uint8_t **output, size_t *output_size, char *error, size_t error_size) {
    *output = NULL; *output_size = 0;
    uhdr_codec_private_t *enc = uhdr_create_encoder();
    if (!enc) { snprintf(error,error_size,"无法分配 HDR 编码器"); return 0; }
    uhdr_raw_image_t hdr = {0};
    hdr.fmt = UHDR_IMG_FMT_64bppRGBAHalfFloat;
    hdr.cg = UHDR_CG_BT_2100; hdr.ct = UHDR_CT_LINEAR; hdr.range = UHDR_CR_FULL_RANGE;
    hdr.w = w; hdr.h = h; hdr.planes[0] = (void*)pixels; hdr.stride[0] = w;
    uhdr_compressed_image_t sdr = {(void*)jpeg, jpeg_size, jpeg_size,
                                 UHDR_CG_BT_709, UHDR_CT_SRGB, UHDR_CR_FULL_RANGE};
    CHECK(uhdr_enc_set_raw_image(enc, &hdr, UHDR_HDR_IMG));
    CHECK(uhdr_enc_set_compressed_image(enc, &sdr, UHDR_SDR_IMG));
    CHECK(uhdr_enc_set_quality(enc, 95, UHDR_GAIN_MAP_IMG));
    CHECK(uhdr_enc_set_gainmap_scale_factor(enc, 2));
    CHECK(uhdr_enc_set_using_multi_channel_gainmap(enc, 1));
    CHECK(uhdr_enc_set_target_display_peak_brightness(enc, peak));
    CHECK(uhdr_enc_set_preset(enc, UHDR_USAGE_BEST_QUALITY));
    CHECK(uhdr_encode(enc));
    uhdr_compressed_image_t *result = uhdr_get_encoded_stream(enc);
    if (!result || !result->data_sz) { snprintf(error,error_size,"HDR 输出为空"); goto fail; }
    *output = malloc(result->data_sz);
    if (!*output) { snprintf(error,error_size,"内存不足"); goto fail; }
    memcpy(*output, result->data, result->data_sz); *output_size = result->data_sz;
    uhdr_release_encoder(enc); return 1;
fail:
    uhdr_release_encoder(enc); return 0;
}
void hlg_free(void *buffer) { free(buffer); }
int hlg_verify(const uint8_t *jpeg, size_t size, unsigned *width, unsigned *height,
               float *max_boost, char *error, size_t error_size) {
    uhdr_codec_private_t *dec = uhdr_create_decoder();
    if (!dec) { snprintf(error,error_size,"无法分配 HDR 解码器"); return 0; }
    uhdr_compressed_image_t image = {(void*)jpeg,size,size,UHDR_CG_UNSPECIFIED,UHDR_CT_UNSPECIFIED,UHDR_CR_UNSPECIFIED};
    CHECK(uhdr_dec_set_image(dec, &image));
    CHECK(uhdr_dec_set_out_img_format(dec, UHDR_IMG_FMT_64bppRGBAHalfFloat));
    CHECK(uhdr_dec_set_out_color_transfer(dec, UHDR_CT_LINEAR));
    CHECK(uhdr_dec_probe(dec));
    *width = uhdr_dec_get_image_width(dec); *height = uhdr_dec_get_image_height(dec);
    uhdr_gainmap_metadata_t *metadata = uhdr_dec_get_gainmap_metadata(dec);
    if (!metadata) { snprintf(error,error_size,"缺少增益图"); goto fail; }
    *max_boost = metadata->hdr_capacity_max;
    CHECK(uhdr_decode(dec));
    uhdr_release_decoder(dec); return 1;
fail:
    uhdr_release_decoder(dec); return 0;
}
