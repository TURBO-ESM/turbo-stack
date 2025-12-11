#include "field_container.h"

#include <AMReX.H>
#include <AMReX_MultiFab.H>
#include <gtest/gtest.h>

#include "amrex_test_environment.h"
#include "cartesian_grid.h"
#include "field.h"
#include "geometry.h"

using namespace turbo;

::testing::Environment* const amrex_env = ::testing::AddGlobalTestEnvironment(new AmrexEnvironment());

class FieldContainerTest : public ::testing::Test
{
   protected:
    void SetUp() override
    {
        double x_min         = 0.0;
        double x_max         = 1.0;
        double y_min         = 0.0;
        double y_max         = 1.0;
        double z_min         = 0.0;
        double z_max         = 1.0;
        geom                 = std::make_shared<CartesianGeometry>(x_min, x_max, y_min, y_max, z_min, z_max);

        std::size_t n_cell_x = 2;
        std::size_t n_cell_y = 3;
        std::size_t n_cell_z = 4;
        grid                 = std::make_shared<CartesianGrid>(geom, n_cell_x, n_cell_y, n_cell_z);
    }

    std::shared_ptr<CartesianGeometry> geom;
    std::shared_ptr<CartesianGrid> grid;
};

//---------------------------------------------------------------------------//
// FieldContainer Tests
//---------------------------------------------------------------------------//

TEST_F(FieldContainerTest, Constructor)
{
    FieldContainer fields(grid);

    {
        std::shared_ptr<Grid> grid_null_ptr = nullptr;
        EXPECT_THROW(FieldContainer field(grid_null_ptr), std::invalid_argument);
    }
}

TEST_F(FieldContainerTest, Insert)
{
    FieldContainer fields(grid);

    {
        Field::NameType name          = "first_field";
        FieldGridStagger stagger      = FieldGridStagger::Nodal;
        const std::size_t n_component = 1;
        const std::size_t n_ghost     = 0;
        std::shared_ptr<Field> field1 = fields.Insert(name, stagger, n_component, n_ghost);
        EXPECT_THROW(fields.Insert(name, stagger, n_component, n_ghost), std::invalid_argument);
    }

    {
        Field::NameType name          = "second_field";
        FieldGridStagger stagger      = FieldGridStagger::CellCentered;
        const std::size_t n_component = 3;
        const std::size_t n_ghost     = 3;
        std::shared_ptr<Field> field1 = fields.Insert(name, stagger, n_component, n_ghost);
    }
}

TEST_F(FieldContainerTest, Contains)
{
    FieldContainer fields(grid);

    Field::NameType name          = "test_nodal_field";
    FieldGridStagger stagger      = FieldGridStagger::Nodal;
    const std::size_t n_component = 1;
    const std::size_t n_ghost     = 0;

    EXPECT_FALSE(fields.Contains(name));
    std::shared_ptr<Field> field1 = fields.Insert(name, stagger, n_component, n_ghost);
    EXPECT_TRUE(fields.Contains(name));
}

TEST_F(FieldContainerTest, Get)
{
    FieldContainer fields(grid);

    Field::NameType name                              = "test_nodal_field";
    FieldGridStagger stagger                          = FieldGridStagger::Nodal;
    const std::size_t n_component                     = 1;
    const std::size_t n_ghost                         = 0;

    std::shared_ptr<Field> field_returned_from_insert = fields.Insert(name, stagger, n_component, n_ghost);
    std::shared_ptr<Field> field_returned_from_get    = fields.Get(name);
    EXPECT_EQ(field_returned_from_insert, field_returned_from_get);
}

TEST_F(FieldContainerTest, Iterators)
{
    FieldContainer fields(grid);

    auto fields_view = fields.Fields();
    EXPECT_TRUE(std::ranges::empty(fields_view));

    Field::NameType name1         = "first_field";
    FieldGridStagger stagger1     = FieldGridStagger::Nodal;
    const std::size_t n_component1 = 1;
    const std::size_t n_ghost1     = 0;
    std::shared_ptr<Field> field1  = fields.Insert(name1, stagger1, n_component1, n_ghost1);

    EXPECT_EQ(std::ranges::size(fields_view), 1);

    Field::NameType name2         = "second_field";
    FieldGridStagger stagger2     = FieldGridStagger::CellCentered;
    const std::size_t n_component2 = 3;
    const std::size_t n_ghost2     = 2;
    std::shared_ptr<Field> field2  = fields.Insert(name2, stagger2, n_component2, n_ghost2);

    EXPECT_EQ(std::ranges::size(fields_view), 2);

    {
        std::set<std::shared_ptr<Field>> field_set;
        for (const auto& field : fields)
        {
            field_set.insert(field);
        }
        EXPECT_EQ(field_set.size(), 2);
        EXPECT_TRUE(field_set.contains(field1));
        EXPECT_TRUE(field_set.contains(field2));
    }

    {
        for (const auto& field : fields_view)
        {
            EXPECT_TRUE(field == field1 || field == field2);
        }
    }


}