#include "raw_layout.h"

#include <gtest/gtest.h>

#include <vector>

namespace just_gamepads {
namespace test {

TEST(ApplyVendorLayout, SonyAxesMoveRightStickYAheadOfTriggers) {
  // RawGameController order for DualShock 4 / DualSense.
  std::vector<double> axes = {0.1, 0.2, 0.3, 0.4 /* L2 */, 0.5 /* R2 */,
                              0.6 /* RY */};
  std::vector<bool> buttons;

  ApplyVendorLayout(kSonyVendorId, &axes, &buttons);

  EXPECT_EQ(axes, (std::vector<double>{0.1, 0.2, 0.3, 0.6, 0.4, 0.5}));
}

TEST(ApplyVendorLayout, SonyFaceButtonsMapByPosition) {
  // Raw order: Square, Cross, Circle, Triangle.
  std::vector<double> axes;
  std::vector<bool> cross = {false, true, false, false};
  std::vector<bool> square = {true, false, false, false};
  std::vector<bool> circle = {false, false, true, false};

  ApplyVendorLayout(kSonyVendorId, &axes, &cross);
  ApplyVendorLayout(kSonyVendorId, &axes, &square);
  ApplyVendorLayout(kSonyVendorId, &axes, &circle);

  EXPECT_EQ(cross, (std::vector<bool>{true, false, false, false}));   // A
  EXPECT_EQ(circle, (std::vector<bool>{false, true, false, false}));  // B
  EXPECT_EQ(square, (std::vector<bool>{false, false, true, false}));  // X
}

TEST(ApplyVendorLayout, OtherVendorsAreUntouched) {
  std::vector<double> axes = {0.1, 0.2, 0.3, 0.4, 0.5, 0.6};
  std::vector<bool> buttons = {true, false, false, false};

  ApplyVendorLayout(0x2DC8, &axes, &buttons);

  EXPECT_EQ(axes, (std::vector<double>{0.1, 0.2, 0.3, 0.4, 0.5, 0.6}));
  EXPECT_EQ(buttons, (std::vector<bool>{true, false, false, false}));
}

TEST(ApplyVendorLayout, ShortSonyReadingsAreLeftAlone) {
  std::vector<double> axes = {0.1, 0.2};
  std::vector<bool> buttons = {true, false};

  ApplyVendorLayout(kSonyVendorId, &axes, &buttons);

  EXPECT_EQ(axes, (std::vector<double>{0.1, 0.2}));
  EXPECT_EQ(buttons, (std::vector<bool>{true, false}));
}

TEST(ToWireAxes, SticksBecomeSignedTriggersStayUnit) {
  const std::vector<double> wire =
      ToWireAxes({0.5, 0.0, 1.0, 0.75, 0.25, 1.0});

  EXPECT_EQ(wire, (std::vector<double>{0.0, -1.0, 1.0, 0.5, 0.25, 1.0}));
}

}  // namespace test
}  // namespace just_gamepads
