#pragma once

#include <set>
#include <string>

namespace turbo {

// Abstract base class for geometry
// Currently all methods for geometry objects, other than the constructor, are essentially getters.
// So there is an implied assumption that geometry objects are immutable after construction.
// Can change later if needed but would need to remember to update member function names to reflect getters, setters, etc.
class Geometry {
public:
    //-----------------------------------------------------------------------//
    // Public Types
    //-----------------------------------------------------------------------//
    using Boundary = std::string;

    //-----------------------------------------------------------------------//
    // Public Member Functions
    //-----------------------------------------------------------------------//
    virtual ~Geometry() = default;
    virtual std::set<Boundary> Boundaries(void) const = 0;

protected:
    //-----------------------------------------------------------------------//
    // Protected Member Functions
    //-----------------------------------------------------------------------//
    std::set<Boundary> boundaries_;
};

// Concrete implementation of a Cartesian geometry
// Also provides cartesian-specific member functions. 
//    Primarily getters for domain extents and lengths associated with Cartesian coordinates x, y, z.
class CartesianGeometry : public Geometry {
public:

    //-----------------------------------------------------------------------//
    // Public Member Functions
    //-----------------------------------------------------------------------//
    CartesianGeometry(double x_min, double x_max, 
                      double y_min, double y_max, 
                      double z_min, double z_max)
        : x_min_(x_min), x_max_(x_max), y_min_(y_min), y_max_(y_max), z_min_(z_min), z_max_(z_max) {

        // Error checking that x_min < x_max, etc.
        if (x_min_ >= x_max_ || y_min_ >= y_max_ || z_min_ >= z_max_) {
            throw std::invalid_argument("Invalid domain extents. Minimum must be less than maximum.");
        }

        boundaries_ = {"x_min", "x_max", "y_min", "y_max", "z_min", "z_max"};

    }

    // Get the boundaries of the domain
    std::set<std::string> Boundaries(void) const override {
        return boundaries_;
    }

    // Get the domain extents
    double XMin() const { return x_min_; }
    double XMax() const { return x_max_; }
    double YMin() const { return y_min_; }
    double YMax() const { return y_max_; }
    double ZMin() const { return z_min_; }
    double ZMax() const { return z_max_; }

    // Get the domain length in each direction
    double LX() const { return x_max_-x_min_; }
    double LY() const { return y_max_-y_min_; }
    double LZ() const { return z_max_-z_min_; }

    //-----------------------------------------------------------------------//
    // Public Data Members
    //-----------------------------------------------------------------------//

private:
    //-----------------------------------------------------------------------//
    // Private Data Members
    //-----------------------------------------------------------------------//
    const double x_min_, x_max_, y_min_, y_max_, z_min_, z_max_;

    //-----------------------------------------------------------------------//
    // Private Member Functions
    //-----------------------------------------------------------------------//

};

} // namespace turbo