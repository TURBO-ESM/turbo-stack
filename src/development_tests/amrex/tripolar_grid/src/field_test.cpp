#include <gtest/gtest.h>

#include <AMReX.H>
#include <AMReX_MultiFab.H>

#include "geometry.h"
#include "grid.h"
#include "field.h"

using namespace turbo;

//---------------------------------------------------------------------------//
// Define a global test environment for AMReX
//---------------------------------------------------------------------------//
class AmrexEnvironment : public ::testing::Environment {
public:
    void SetUp() override {
        int argc = 1;
        char arg0[] = "test";
        char* argv_array[] = { arg0, nullptr };
        char** argv = argv_array;
        amrex::Initialize(argc, argv);
        std::cout << "AmrexEnvironment SetUp called\n";
    }
    void TearDown() override {
        amrex::Finalize();
        std::cout << "AmrexEnvironment TearDown called\n";
    }
};

::testing::Environment* const amrex_env = ::testing::AddGlobalTestEnvironment(new AmrexEnvironment());


//---------------------------------------------------------------------------//
// Define a test fixture for field tests
//---------------------------------------------------------------------------//

class FieldTest : public ::testing::Test {
protected:
  void SetUp() override {
    double x_min = 0.0;
    double x_max = 1.0;
    double y_min = 0.0;
    double y_max = 1.0;
    double z_min = 0.0;
    double z_max = 1.0;
    geom = std::make_shared<CartesianGeometry>(x_min, x_max, y_min, y_max, z_min, z_max);

    std::size_t n_cell_x = 2;
    std::size_t n_cell_y = 3;
    std::size_t n_cell_z = 4;
    grid = std::make_shared<CartesianGrid>(geom, n_cell_x, n_cell_y, n_cell_z);
  }

  std::shared_ptr<CartesianGeometry> geom;
  std::shared_ptr<CartesianGrid> grid;
};

//---------------------------------------------------------------------------//
// Field tests
//---------------------------------------------------------------------------//

TEST_F(FieldTest, Constructor) {

  std::string name = "test_field";
  FieldGridStagger stagger = FieldGridStagger::Nodal;
  std::size_t n_component = 1;
  std::size_t n_ghost = 0;

  Field field(name, grid, stagger, n_component, n_ghost);

  // One off helper function to convert FieldGridStagger to string for naming fields in the following loop
  auto FieldGridStaggerToString = [](FieldGridStagger field_grid_stagger) -> std::string {
    switch (field_grid_stagger) {
      case FieldGridStagger::Nodal:        return "Nodal";
      case FieldGridStagger::CellCentered: return "CellCentered";
      case FieldGridStagger::IFace:        return "IFace";
      case FieldGridStagger::JFace:        return "JFace";
      case FieldGridStagger::KFace:        return "KFace";
      default: throw std::invalid_argument("FieldGridStaggerToString Invalid FieldGridStagger specified.");
    }
  };

  for (std::size_t n_component : {1,3}) {
    for (std::size_t n_ghost : {0,1,2}) {
      for (const FieldGridStagger field_stagger : {FieldGridStagger::Nodal, FieldGridStagger::CellCentered, FieldGridStagger::IFace, FieldGridStagger::JFace, FieldGridStagger::KFace}) {

        std::string field_name = "field_" + FieldGridStaggerToString(field_stagger) + "_ncomp_" + std::to_string(n_component) + "_nghost_" + std::to_string(n_ghost);
        Field field(field_name, grid, field_stagger, n_component, n_ghost);

        std::shared_ptr<amrex::MultiFab> mf = field.multifab;

        EXPECT_TRUE(mf != nullptr);
        EXPECT_TRUE(mf->ok());
        EXPECT_EQ(mf->nComp(), n_component);
        EXPECT_EQ(mf->nGrow(), n_ghost);

        // Get the box that covers the entire MultiFab
        const amrex::Box& box = mf->boxArray().minimalBox();

        //  Given the field location, check the amrex indexing in each direction and the box size is correct
        switch (field.field_grid_stagger)
        {
          case FieldGridStagger::Nodal:
            EXPECT_TRUE(mf->is_nodal(0));
            EXPECT_TRUE(mf->is_nodal(1));
            EXPECT_TRUE(mf->is_nodal(2));
            EXPECT_EQ(box.length(),   amrex::IntVect(grid->NNodeI(), grid->NNodeJ(), grid->NNodeK()));
            EXPECT_EQ(box.smallEnd(), amrex::IntVect(0, 0, 0));
            EXPECT_EQ(box.bigEnd(),   amrex::IntVect(grid->NNodeI()-1, grid->NNodeJ()-1, grid->NNodeK()-1));
            break;
          case FieldGridStagger::CellCentered:
            EXPECT_FALSE(mf->is_nodal(0));
            EXPECT_FALSE(mf->is_nodal(1));
            EXPECT_FALSE(mf->is_nodal(2));
            EXPECT_EQ(box.length(),   amrex::IntVect(grid->NCellI(), grid->NCellJ(), grid->NCellK()));
            EXPECT_EQ(box.smallEnd(), amrex::IntVect(0, 0, 0));
            EXPECT_EQ(box.bigEnd(),   amrex::IntVect(grid->NCellI()-1, grid->NCellJ()-1, grid->NCellK()-1));
            break;
          case FieldGridStagger::IFace:
            EXPECT_TRUE(mf->is_nodal(0));
            EXPECT_FALSE(mf->is_nodal(1));
            EXPECT_FALSE(mf->is_nodal(2));
            EXPECT_EQ(box.length(),   amrex::IntVect(grid->NNodeI(), grid->NCellJ(), grid->NCellK()));
            EXPECT_EQ(box.smallEnd(), amrex::IntVect(0, 0, 0));
            EXPECT_EQ(box.bigEnd(),   amrex::IntVect(grid->NNodeI()-1, grid->NCellJ()-1, grid->NCellK()-1));
            break;
          case FieldGridStagger::JFace:
            EXPECT_FALSE(mf->is_nodal(0));
            EXPECT_TRUE(mf->is_nodal(1));
            EXPECT_FALSE(mf->is_nodal(2));
            EXPECT_EQ(box.length(),   amrex::IntVect(grid->NCellI(), grid->NNodeJ(), grid->NCellK()));
            EXPECT_EQ(box.smallEnd(), amrex::IntVect(0, 0, 0));
            EXPECT_EQ(box.bigEnd(),   amrex::IntVect(grid->NCellI()-1, grid->NNodeJ()-1, grid->NCellK()-1));
            break;
          case FieldGridStagger::KFace:
            EXPECT_FALSE(mf->is_nodal(0));
            EXPECT_FALSE(mf->is_nodal(1));
            EXPECT_TRUE(mf->is_nodal(2));
            EXPECT_EQ(box.length(),   amrex::IntVect(grid->NCellI(), grid->NCellJ(), grid->NNodeK()));
            EXPECT_EQ(box.smallEnd(), amrex::IntVect(0, 0, 0));
            EXPECT_EQ(box.bigEnd(),   amrex::IntVect(grid->NCellI()-1, grid->NCellJ()-1, grid->NNodeK()-1));
            break;
          default:
              throw std::invalid_argument("FieldContainer:: Invalid FieldGridStagger specified.");
        }

        // Test adding a field with a duplicate name
  //EXPECT_THROW(fields.Insert(field_name, FieldGridStagger::Nodal, n_component, n_ghost), std::invalid_argument);
      }
    }
  }

}

TEST_F(FieldTest, WriteHDF5) {

  std::string name = "test_field";
  FieldGridStagger stagger = FieldGridStagger::Nodal;
  std::size_t n_component = 1;
  std::size_t n_ghost = 0;
  Field field(name, grid, stagger, n_component, n_ghost);

  const std::string filename = "Test_Output_Field_WriteHDF5.h5";
  const hid_t file_id = H5Fcreate(filename.c_str(), H5F_ACC_TRUNC, H5P_DEFAULT, H5P_DEFAULT);
  field.WriteHDF5(file_id);
  H5Fclose(file_id);

}

//---------------------------------------------------------------------------//
// FieldContainer Tests
//---------------------------------------------------------------------------//
// Should just move this to another file later

class FieldContainerTest : public ::testing::Test {
protected:
  void SetUp() override {
    double x_min = 0.0;
    double x_max = 1.0;
    double y_min = 0.0;
    double y_max = 1.0;
    double z_min = 0.0;
    double z_max = 1.0;
    geom = std::make_shared<CartesianGeometry>(x_min, x_max, y_min, y_max, z_min, z_max);

    std::size_t n_cell_x = 2;
    std::size_t n_cell_y = 3;
    std::size_t n_cell_z = 4;
    grid = std::make_shared<CartesianGrid>(geom, n_cell_x, n_cell_y, n_cell_z);
  }

  std::shared_ptr<CartesianGeometry> geom;
  std::shared_ptr<CartesianGrid> grid;
};

TEST_F(FieldContainerTest, Constructor) {
  FieldContainer fields(grid);

  {
    std::shared_ptr<Grid> grid_null_ptr = nullptr;
    EXPECT_THROW(FieldContainer field(grid_null_ptr), std::invalid_argument);
  }

}

TEST_F(FieldContainerTest, Insert) {

  FieldContainer fields(grid);

  {
    std::string name = "first_field";
    FieldGridStagger stagger = FieldGridStagger::Nodal;
    const std::size_t n_component = 1;
    const std::size_t n_ghost = 0;
    std::shared_ptr<Field> field1 = fields.Insert(name, stagger, n_component, n_ghost);
    EXPECT_THROW(fields.Insert(name, stagger, n_component, n_ghost), std::invalid_argument);
  }

  {
    std::string name = "second_field";
    FieldGridStagger stagger = FieldGridStagger::CellCentered;
    const std::size_t n_component = 3;
    const std::size_t n_ghost = 3;
    std::shared_ptr<Field> field1 = fields.Insert(name, stagger, n_component, n_ghost);
  }

}

TEST_F(FieldContainerTest, WriteHDF5) {

  FieldContainer fields(grid);

  auto scalar_mf = fields.Insert("cell_scalar_field", FieldGridStagger::CellCentered, 1, 1);
  auto vector_mf = fields.Insert("cell_vector_field", FieldGridStagger::CellCentered, 3, 1);

  const std::string filename = "Test_Output_FieldContainer_WriteHDF5.h5";
  const hid_t file_id = H5Fcreate(filename.c_str(), H5F_ACC_TRUNC, H5P_DEFAULT, H5P_DEFAULT);
  fields.WriteHDF5(file_id);
  H5Fclose(file_id);

}
