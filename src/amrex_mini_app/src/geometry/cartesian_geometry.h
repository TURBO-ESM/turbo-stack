#pragma once

#include <set>
#include <stdexcept>
#include <string>

#include "geometry.h"

namespace turbo
{

/**
 * @brief Concrete implementation of a Cartesian geometry.
 *
 * Provides cartesian-specific member functions, primarily getters for domain extents and lengths
 * associated with Cartesian coordinates x, y, z.
 */
class CartesianGeometry : public Geometry
{
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
    CartesianGeometry(double x_min, double x_max, double y_min, double y_max, double z_min, double z_max);

    /**
     * @brief Get the minimum x-coordinate of the domain.
     * @return Minimum x value.
     */
    double XMin() const noexcept;

    /**
     * @brief Get the maximum x-coordinate of the domain.
     * @return Maximum x value.
     */
    double XMax() const noexcept;

    /**
     * @brief Get the minimum y-coordinate of the domain.
     * @return Minimum y value.
     */
    double YMin() const noexcept;

    /**
     * @brief Get the maximum y-coordinate of the domain.
     * @return Maximum y value.
     */
    double YMax() const noexcept;

    /**
     * @brief Get the minimum z-coordinate of the domain.
     * @return Minimum z value.
     */
    double ZMin() const noexcept;

    /**
     * @brief Get the maximum z-coordinate of the domain.
     * @return Maximum z value.
     */
    double ZMax() const noexcept;

    /**
     * @brief Get the domain length in the x direction.
     * @return Length in x.
     */
    double LX() const noexcept;

    /**
     * @brief Get the domain length in the y direction.
     * @return Length in y.
     */
    double LY() const noexcept;

    /**
     * @brief Get the domain length in the z direction.
     * @return Length in z.
     */
    double LZ() const noexcept;

   private:
    //-----------------------------------------------------------------------//
    // Private Data Members
    //-----------------------------------------------------------------------//
    /**
     * @brief Domain extents for x, y, z coordinates.
     */
    const double x_min_, x_max_, y_min_, y_max_, z_min_, z_max_;
};

}  // namespace turbo
