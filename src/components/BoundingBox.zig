pub const BoundingBox = struct {
    active: bool = true,

    // Configuration (unscaled)
    width: f32 = 0,      // Custom collision box width (0 = use sprite)
    height: f32 = 0,     // Custom collision box height (0 = use sprite)
    offset_x: f32 = 0,   // Offset from sprite center
    offset_y: f32 = 0,

    // Computed bounding box (world space, calculated by Collision system)
    bbox_x: f32 = 0,         // Top-left corner X
    bbox_y: f32 = 0,         // Top-left corner Y
    bbox_width: f32 = 0,     // Scaled width
    bbox_height: f32 = 0,    // Scaled height
};
