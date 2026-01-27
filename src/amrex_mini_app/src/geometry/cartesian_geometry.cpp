#include <stdexcept>
#include <string>

#include "cartesian_geometry.h"

namespace turbo
{

CartesianGeometry::CartesianGeometry(double x_min, double x_max, double y_min, double y_max, double z_min, double z_max)
    : Geometry({"x_min", "x_max", "y_min", "y_max", "z_min", "z_max"}),
      x_min_(x_min),
      x_max_(x_max),
      y_min_(y_min),
      y_max_(y_max),
      z_min_(z_min),
      z_max_(z_max)
{
    // Error checking that x_min < x_max, etc.
    if (x_min_ >= x_max_ || y_min_ >= y_max_ || z_min_ >= z_max_)
    {
        throw std::invalid_argument("Invalid domain extents. Minimum must be less than maximum.");
    }
}

double CartesianGeometry::XMin() const noexcept { return x_min_; }

double CartesianGeometry::XMax() const noexcept { return x_max_; }

double CartesianGeometry::YMin() const noexcept { return y_min_; }

double CartesianGeometry::YMax() const noexcept { return y_max_; }

double CartesianGeometry::ZMin() const noexcept { return z_min_; }

double CartesianGeometry::ZMax() const noexcept { return z_max_; }

double CartesianGeometry::LX() const noexcept { return x_max_ - x_min_; }

double CartesianGeometry::LY() const noexcept { return y_max_ - y_min_; }

double CartesianGeometry::LZ() const noexcept { return z_max_ - z_min_; }

}  // namespace turbo
