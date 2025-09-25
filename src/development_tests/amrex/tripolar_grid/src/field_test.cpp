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

  for (std::size_t n_component : {1,3}) {
    for (std::size_t n_ghost : {0,1,2}) {
      for (const FieldGridStagger field_stagger : {FieldGridStagger::Nodal, FieldGridStagger::CellCentered, FieldGridStagger::IFace, FieldGridStagger::JFace, FieldGridStagger::KFace}) {

        std::string field_name = "field_" + FieldGridStaggerToString(field_stagger) + "_ncomp_" + std::to_string(n_component) + "_nghost_" + std::to_string(n_ghost);
        Field field(field_name, grid, field_stagger, n_component, n_ghost);

        EXPECT_EQ(field.name, field_name);
        EXPECT_EQ(field.field_grid_stagger, field_stagger);

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

      }
    }
  }

}

TEST_F(FieldTest, StaggerChecks) {

  std::size_t n_component = 1;
  std::size_t n_ghost = 0;

  // The field location checks should report grid location correctly for all grid staggers
  {
    std::string name = "nodal_field";
    FieldGridStagger stagger = FieldGridStagger::Nodal;
    Field field(name, grid, stagger, n_component, n_ghost);

    EXPECT_TRUE(field.IsNodal());
    EXPECT_FALSE(field.IsCellCentered());
    EXPECT_FALSE(field.IsXFaceCentered());
    EXPECT_FALSE(field.IsYFaceCentered());
    EXPECT_FALSE(field.IsZFaceCentered());
  }

  {
    std::string name = "cell_centered_field";
    FieldGridStagger stagger = FieldGridStagger::CellCentered;
    Field field(name, grid, stagger, n_component, n_ghost);

    EXPECT_FALSE(field.IsNodal());
    EXPECT_TRUE(field.IsCellCentered());
    EXPECT_FALSE(field.IsXFaceCentered());
    EXPECT_FALSE(field.IsYFaceCentered());
    EXPECT_FALSE(field.IsZFaceCentered());
  }

  {
    std::string name = "x_face_centered_field";
    FieldGridStagger stagger = FieldGridStagger::IFace;
    Field field(name, grid, stagger, n_component, n_ghost);

    EXPECT_FALSE(field.IsNodal());
    EXPECT_FALSE(field.IsCellCentered());
    EXPECT_TRUE(field.IsXFaceCentered());
    EXPECT_FALSE(field.IsYFaceCentered());
    EXPECT_FALSE(field.IsZFaceCentered());
  }

  {
    std::string name = "y_face_centered_field";
    FieldGridStagger stagger = FieldGridStagger::JFace;
    Field field(name, grid, stagger, n_component, n_ghost);

    EXPECT_FALSE(field.IsNodal());
    EXPECT_FALSE(field.IsCellCentered());
    EXPECT_FALSE(field.IsXFaceCentered());
    EXPECT_TRUE(field.IsYFaceCentered());
    EXPECT_FALSE(field.IsZFaceCentered());
  }

  {
    std::string name = "z_face_centered_field";
    FieldGridStagger stagger = FieldGridStagger::KFace;
    Field field(name, grid, stagger, n_component, n_ghost);

    EXPECT_FALSE(field.IsNodal());
    EXPECT_FALSE(field.IsCellCentered());
    EXPECT_FALSE(field.IsXFaceCentered());
    EXPECT_FALSE(field.IsYFaceCentered());
    EXPECT_TRUE(field.IsZFaceCentered());
  }

}

TEST_F(FieldTest, GetGridPoint) {

  // Helper function to convert FieldGridStagger to the upper loop bounds in each direction for the grid based on the stagger
  auto GridSizeHelper = [this](FieldGridStagger field_grid_stagger) -> std::tuple<std::size_t, std::size_t, std::size_t> {
    switch (field_grid_stagger) {
      case FieldGridStagger::Nodal:        return std::make_tuple(this->grid->NNodeI(), this->grid->NNodeJ(), this->grid->NNodeK());
      case FieldGridStagger::CellCentered: return std::make_tuple(this->grid->NCellI(), this->grid->NCellJ(), this->grid->NCellK());
      case FieldGridStagger::IFace:        return std::make_tuple(this->grid->NNodeI(), this->grid->NCellJ(), this->grid->NCellK());
      case FieldGridStagger::JFace:        return std::make_tuple(this->grid->NCellI(), this->grid->NNodeJ(), this->grid->NCellK());
      case FieldGridStagger::KFace:        return std::make_tuple(this->grid->NCellI(), this->grid->NCellJ(), this->grid->NNodeK());
      default: throw std::invalid_argument("GridUpperLoopBoundsHelper invalid FieldGridStagger specified.");
    }
  };

  // Helper function to convert FieldGridStagger to the the correct grid location function
    auto GridLocationHelper = [this](FieldGridStagger field_grid_stagger, std::size_t i, std::size_t j, std::size_t k) -> Grid::Point {
    switch (field_grid_stagger) {
      case FieldGridStagger::Nodal:        return this->grid->Node(i,j,k);
      case FieldGridStagger::CellCentered: return this->grid->CellCenter(i,j,k);
      case FieldGridStagger::IFace:        return this->grid->IFace(i,j,k);
      case FieldGridStagger::JFace:        return this->grid->JFace(i,j,k);
      case FieldGridStagger::KFace:        return this->grid->KFace(i,j,k);
      default: throw std::invalid_argument("GridLocationHelper invalid FieldGridStagger specified.");
    }
  };

  // Use the same n_component and n_ghost for all the fields in this test. Should not really matter for this test.
  std::size_t n_component = 1;
  std::size_t n_ghost = 0;

  for (const FieldGridStagger field_grid_stagger : {FieldGridStagger::Nodal, FieldGridStagger::CellCentered, FieldGridStagger::IFace, FieldGridStagger::JFace, FieldGridStagger::KFace}) {

    std::string field_name = "field_at_" + FieldGridStaggerToString(field_grid_stagger);
    Field field(field_name, grid, field_grid_stagger, n_component, n_ghost);

    auto [i_size, j_size, k_size] = GridSizeHelper(field_grid_stagger);

  // Loop over grid, for this stagger, and and compare with the location of each grid point with the location from field.GetGridPoint. They should match.
    for (std::size_t i=0; i<i_size; ++i) {
      for (std::size_t j=0; j<j_size; ++j) {
        for (std::size_t k=0; k<k_size; ++k) {
            Grid::Point grid_location  = GridLocationHelper(field_grid_stagger, i, j, k);
            Grid::Point field_location = field.GetGridPoint(i,j,k);
            EXPECT_EQ(grid_location, field_location) << "Field location does not match expected location for field stagger " << FieldGridStaggerToString(field_grid_stagger) << " at indices (" << i << "," << j << "," << k << ")";
        }
      }
    }

    // Loop over the multi-fab associated with the field, find the location of the field and compare with the corresponding location in the grid. They should match.
    // Basically checking the same thing as the previous loop but this one is using the amrex indexing accessed thought the underlying multifab. This could also be run in parallel or on a GPU.
    // I could see users wanting to loop over the field or the multifab directly and get the location of the field at those indices. So testing both ways here.
    for (amrex::MFIter mfi(*field.multifab); mfi.isValid(); ++mfi) {
        amrex::ParallelFor(mfi.validbox(), [=,this] AMREX_GPU_DEVICE(int i, int j, int k) {
            Grid::Point grid_location = GridLocationHelper(field_grid_stagger, i, j, k);
            Grid::Point field_location = field.GetGridPoint(i,j,k);
            EXPECT_EQ(grid_location, field_location);
        });
    }

  }

  // Test for for locations specific to a nodal Nodal field. I generalized and moved all this into the loop above that covers all possible field grid staggering. So this is redundant now. Probably should just get rid of this.
  //{
  //  std::string name = "nodal_field";
  //  FieldGridStagger stagger = FieldGridStagger::Nodal;
  //  Field field(name, grid, stagger, n_component, n_ghost);

  //  // Loop over grid, for this stagger, and and compare with the location for each grid point returned from the field.GetGridPoint. They should match.
  //  for (std::size_t i=0; i<grid->NNodeI(); ++i) {
  //    for (std::size_t j=0; j<grid->NNodeJ(); ++j) {
  //      for (std::size_t k=0; k<grid->NNodeK(); ++k) {
  //        EXPECT_EQ(grid->Node(i,j,k), field.GetGridPoint(i,j,k));
  //      }
  //    }
  //  }

  //  // Loop over the multi-fab associated with the field and compare with the corresponding location in the grid. They should also match.
  //  for (amrex::MFIter mfi(*field.multifab); mfi.isValid(); ++mfi) {
  //      amrex::ParallelFor(mfi.validbox(), [=,this] AMREX_GPU_DEVICE(int i, int j, int k) {
  //          EXPECT_EQ(field.GetGridPoint(i,j,k), grid->Node(i,j,k));
  //      });
  //  }
  //}

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
