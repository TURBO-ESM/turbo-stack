#include "cartesian_geometry.h"

#include <gtest/gtest.h>

#include <set>
#include <string>

using namespace turbo;

TEST(CartesianGeometry, Constructor)
{
    const double x_min = 0.0;
    const double x_max = 1.0;
    const double y_min = -1.0;
    const double y_max = 1.0;
    const double z_min = 4.0;
    const double z_max = 5.5;

    // Invalid domain extents should throw
    EXPECT_THROW(CartesianGeometry geom_invalid(x_max, x_min, y_min, y_max, z_min, z_max), std::invalid_argument);
    EXPECT_THROW(CartesianGeometry geom_invalid(x_min, x_max, y_max, y_min, z_min, z_max), std::invalid_argument);
    EXPECT_THROW(CartesianGeometry geom_invalid(x_min, x_max, y_min, y_max, z_max, z_min), std::invalid_argument);

    CartesianGeometry geom(x_min, x_max, y_min, y_max, z_min, z_max);

    // Check that domain extents are set correctly
    EXPECT_DOUBLE_EQ(geom.XMin(), x_min);
    EXPECT_DOUBLE_EQ(geom.XMax(), x_max);
    EXPECT_DOUBLE_EQ(geom.YMin(), y_min);
    EXPECT_DOUBLE_EQ(geom.YMax(), y_max);
    EXPECT_DOUBLE_EQ(geom.ZMin(), z_min);
    EXPECT_DOUBLE_EQ(geom.ZMax(), z_max);

    // Check that boundaries are set correctly
    std::set<Geometry::Boundary> boundary_expected = {"x_min", "x_max", "y_min", "y_max", "z_min", "z_max"};
    EXPECT_EQ(boundary_expected, geom.Boundaries());
}

TEST(CartesianGeometry, DomainLengths)
{
    const double x_min = 0.0;
    const double x_max = 1.0;
    const double y_min = -1.0;
    const double y_max = 1.0;
    const double z_min = 4.0;
    const double z_max = 5.5;

    CartesianGeometry geom(x_min, x_max, y_min, y_max, z_min, z_max);

    EXPECT_DOUBLE_EQ(geom.LX(), x_max - x_min);
    EXPECT_DOUBLE_EQ(geom.LY(), y_max - y_min);
    EXPECT_DOUBLE_EQ(geom.LZ(), z_max - z_min);

    // Lengths should always be positive
    EXPECT_GT(geom.LX(), 0.0);
    EXPECT_GT(geom.LY(), 0.0);
    EXPECT_GT(geom.LZ(), 0.0);
}
