#pragma once

#include <cstddef>
#include <memory>
#include <string>
#include <set>

#include "grid.h"
#include "field.h"

namespace turbo {

class FieldContainer {
public:

    //-----------------------------------------------------------------------//
    // Public Member Types
    //-----------------------------------------------------------------------//
    // Const iterator types for external iteration
    using const_iterator = std::set<std::shared_ptr<Field>>::const_iterator;

    //-----------------------------------------------------------------------//
    // Public Member Functions
    //-----------------------------------------------------------------------//

    // Constructors
    FieldContainer(const std::shared_ptr<Grid>& grid);

    bool Contains(const std::string& name) const noexcept;

    std::shared_ptr<Field> Insert(const std::string& name, const FieldGridStagger stagger, const std::size_t n_component, const std::size_t n_ghost);

    std::shared_ptr<Field> Get(const std::string& name) const;

    // Const-only iteration support
    const_iterator begin() const;
    const_iterator end() const;

private:

    //-----------------------------------------------------------------------//
    // Private Data Members
    //-----------------------------------------------------------------------//
    const std::shared_ptr<Grid> grid_;
    std::set<std::shared_ptr<Field>> fields_;

};

} // namespace turbo