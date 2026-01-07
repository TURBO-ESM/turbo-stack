#pragma once

#include <set>
#include <stdexcept>
#include <string>

namespace turbo
{

/**
 * @brief Abstract base class for geometry objects.
 *
 * All methods for geometry objects, other than the constructor, are essentially getters.
 * There is an implied assumption that geometry objects are immutable after construction.
 * This can be changed later if needed, but member function names should be updated to reflect getters, setters, etc.
 */
class Geometry
{
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
     * @brief Constructor for Geometry.
     * @param boundaries Set of boundary names for the geometry.
     */
    Geometry(std::set<Boundary> boundaries = {}) : boundaries_(boundaries) {}

    /**
     * @brief Virtual destructor for Geometry. Needed because this is an abstract base class.
     */
    virtual ~Geometry() = default;

    /**
     * @brief Get the set of boundaries for the geometry.
     * @return Set of boundary names.
     */
    std::set<Boundary> Boundaries() const noexcept { return boundaries_; }

   protected:
    //-----------------------------------------------------------------------//
    // Protected Member Data
    //-----------------------------------------------------------------------//

    /**
     * @brief Set of boundary names for the geometry.
     */
    std::set<Boundary> boundaries_;
};


}  // namespace turbo