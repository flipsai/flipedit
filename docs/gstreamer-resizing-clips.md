
# Resizing and Positioning Clips with GStreamer

This document explains the correct GStreamer pipeline configuration to resize a video clip to specific dimensions and then position it on a larger canvas without causing stretching. This is a common requirement in video editing applications for features like Picture-in-Picture or for allowing users to freely transform clips on a canvas.

## The Goal

The objective is to take a source video clip and transform it so that it has a specific width and height (e.g., `320x240` pixels) and is positioned at a specific coordinate (e.g., `x=100, y=50`) on a larger output texture (e.g., `1920x1080`).

A common mistake is to only use `videoscale` or only `videobox`, which leads to the clip being stretched to fill the entire output canvas.

## The GStreamer Elements

The solution requires a chain of three GStreamer elements applied in a specific order:

1.  **`videoscale`**: This element handles the resizing of the video stream. It takes the raw video frames from the source clip and scales them up or down. By itself, it doesn't know the final output dimensions and will simply pass the scaled frames down the pipeline.
    -   **Important Property**: `add-borders`. By default, this is `true`, which means `videoscale` will preserve the original aspect ratio, adding black borders (letterboxing/pillarboxing) if the target dimensions have a different ratio. To force the video to stretch to the exact target dimensions, you must set `add-borders` to `false`.

2.  **`capsfilter`**: This element is crucial for "locking in" the new dimensions after scaling. It acts as a gatekeeper, setting the capabilities (`caps`) of the video stream to a specific width and height. Any downstream element will now see the stream as having these new, smaller dimensions.
    -   **Important Property**: `pixel-aspect-ratio`. Source videos can have non-square pixels (a non-1/1 Pixel Aspect Ratio, or PAR). GStreamer will try to preserve this ratio by default. To ensure your clip is scaled to the *exact* pixel dimensions you request, you must add `pixel-aspect-ratio=1/1` to the caps to force square pixels.

3.  **`videobox`**: This element is used for positioning. It takes the resized video stream (whose dimensions are now constrained by `capsfilter`) and places it onto a larger background. It adds borders to fill the remaining space. We use its `left` and `top` properties to control the X and Y position of the clip.

## Pipeline Order

The order of these effects is critical for the process to work correctly:

`source-clip -> videoscale -> capsfilter -> videobox -> final-output`

1.  `videoscale` first changes the clip's resolution.
2.  `capsfilter` sets the stream's properties to match the new resolution.
3.  `videobox` then takes this correctly-sized stream and positions it on the final, larger canvas.

## Implementation in GES (GStreamer Editing Services)

In a GES-based application, these GStreamer elements are applied as `ges::Effect` objects to a `ges::Clip`.

Here is a Rust code snippet demonstrating how to implement this using the `gstreamer-rs` bindings. This function applies the necessary transform effects to a `ges::Clip`.

```rust
fn apply_video_transforms(ges_clip: &ges::Clip, clip_data: &TimelineClip) -> Result<()> {
    use ges::prelude::*;
    use gst::prelude::*;

    info!("Applying transforms to clip: X={}, Y={}, W={}, H={}",
          clip_data.preview_position_x,
          clip_data.preview_position_y,
          clip_data.preview_width,
          clip_data.preview_height);

    // 1. Scale the video to the desired preview size
    let videoscale_effect = ges::Effect::new("videoscale")?;
    // Use nearest-neighbor for speed and disable aspect ratio preservation
    ges::prelude::TimelineElementExt::set_child_property(&videoscale_effect, "method", &0i32.to_value())?;
    ges::prelude::TimelineElementExt::set_child_property(&videoscale_effect, "add-borders", &false.to_value())?;
    ges_clip.add(&videoscale_effect)?;

    // 2. Use a capsfilter to enforce the scaled dimensions
    let capsfilter_effect = ges::Effect::new("capsfilter")?;
    let caps = gst::Caps::builder("video/x-raw")
        .field("width", clip_data.preview_width as i32)
        .field("height", clip_data.preview_height as i32)
        .field("pixel-aspect-ratio", gst::Fraction::new(1, 1)) // Force square pixels
        .build();
    ges::prelude::TimelineElementExt::set_child_property(&capsfilter_effect, "caps", &caps.to_value())?;
    ges_clip.add(&capsfilter_effect)?;

    // 3. Position the scaled video on the canvas using videobox
    let videobox_effect = ges::Effect::new("videobox")?;
    let left_border = clip_data.preview_position_x as i32;
    let top_border = clip_data.preview_position_y as i32;
    ges::prelude::TimelineElementExt::set_child_property(&videobox_effect, "left", &left_border.to_value())?;
    ges::prelude::TimelineElementExt::set_child_property(&videobox_effect, "top", &top_border.to_value())?;
    ges_clip.add(&videobox_effect)?;
    
    info!("Applied video transform effects: position=({},{}), size=({},{})",
          clip_data.preview_position_x, clip_data.preview_position_y,
          clip_data.preview_width, clip_data.preview_height);

    Ok(())
}
``` 