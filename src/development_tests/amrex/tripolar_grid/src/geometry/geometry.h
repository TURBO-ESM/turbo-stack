#pragma once

#include <set>
#include <string>

namespace turbo {

/**
 * @brief Abstract base class for geometry objects.
 *
 * All methods for geometry objects, other than the constructor, are essentially getters.
 * There is an implied assumption that geometry objects are immutable after construction.
 * This can be changed later if needed, but member function names should be updated to reflect getters, setters, etc.
 */
class Geometry {
public:
    //-----------------------------------------------------------------------//
    // Public Types
    //-----------------------------------------------------------------------//

    /**
     * @brief Type alias for boundary representation.
     */
    using Boundary = std::string;


    //-----------------------------------------------------------------------//
    // Public Member Functions
    //-----------------------------------------------------------------------//

    /**
     * @brief Virtual destructor for Geometry. Needed because this is an abstract base class.
     */
    virtual ~Geometry() = default;

    /**
     * @brief Get the set of boundaries for the geometry.
     * @return Set of boundary names.
     */
    virtual std::set<Boundary> Boundaries(void) const = 0;

protected:
    //-----------------------------------------------------------------------//
    // Protected Member Data
    //-----------------------------------------------------------------------//

    /**
     * @brief Set of boundary names for the geometry.
     */
    std::set<Boundary> boundaries_;
};

/**
 * @brief Concrete implementation of a Cartesian geometry.
 *
 * Provides cartesian-specific member functions, primarily getters for domain extents and lengths
 * associated with Cartesian coordinates x, y, z.
 */
class CartesianGeometry : public Geometry {
public:

    //-----------------------------------------------------------------------//
    // Public Member Functions
    //-----------------------------------------------------------------------//

    /**
     * @brief Construct a CartesianGeometry object with domain extents.
     * @param x_min Minimum x-coordinate
     * @param x_max Maximum x-coordinate
     * @param y_min Minimum y-coordinate
     * @param y_max Maximum y-coordinate
     * @param z_min Minimum z-coordinate
     * @param z_max Maximum z-coordinate
     * @throws std::invalid_argument if any coordinate minimum >= maximum
     */
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

    /**
     * @brief Get the boundaries of the domain.
     * @return Set of boundary names.
     */
    std::set<std::string> Boundaries(void) const override {
        return boundaries_;
    }

    /**
     * @brief Get the minimum x-coordinate of the domain.
     * @return Minimum x value.
     */
    double XMin() const noexcept { return x_min_; }

    /**
     * @brief Get the maximum x-coordinate of the domain.
     * @return Maximum x value.
     */
    double XMax() const noexcept { return x_max_; }

    /**
     * @brief Get the minimum y-coordinate of the domain.
     * @return Minimum y value.
     */
    double YMin() const noexcept { return y_min_; }

    /**
     * @brief Get the maximum y-coordinate of the domain.
     * @return Maximum y value.
     */
    double YMax() const noexcept { return y_max_; }

    /**
     * @brief Get the minimum z-coordinate of the domain.
     * @return Minimum z value.
     */
    double ZMin() const noexcept { return z_min_; }

    /**
     * @brief Get the maximum z-coordinate of the domain.
     * @return Maximum z value.
     */
    double ZMax() const noexcept { return z_max_; }

    /**
     * @brief Get the domain length in the x direction.
     * @return Length in x.
     */
    double LX() const noexcept { return x_max_-x_min_; }

    /**
     * @brief Get the domain length in the y direction.
     * @return Length in y.
     */
    double LY() const noexcept { return y_max_-y_min_; }

    /**
     * @brief Get the domain length in the z direction.
     * @return Length in z.
     */
    double LZ() const noexcept { return z_max_-z_min_; }

private:
    //-----------------------------------------------------------------------//
    // Private Data Members
    //-----------------------------------------------------------------------//
    /**
     * @brief Domain extents for x, y, z coordinates.
     */
    const double x_min_, x_max_, y_min_, y_max_, z_min_, z_max_;

};

} // namespace turbo